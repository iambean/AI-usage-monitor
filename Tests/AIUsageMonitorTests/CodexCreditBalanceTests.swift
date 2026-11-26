import Foundation
import XCTest

@testable import AIUsageMonitor

final class CodexCreditBalanceTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_788_800_000)

  func testDefaultCreditsAreParsedAndSparkCreditsAreIgnored() throws {
    let state = try parse(
      root(
        defaultCredits: credits(balance: "12345.6789", expiresAt: 1_791_173_939),
        sparkCredits: credits(balance: "999.25")
      )
    )

    let parsed = try XCTUnwrap(state.codexCredits)
    XCTAssertEqual(parsed.amount, .balance(decimal("12345.6789")))
    XCTAssertEqual(parsed.expiresAt, Date(timeIntervalSince1970: 1_791_173_939))
  }

  func testLegacyRateLimitsCreditsAreUsedWhenByIDIsAbsent() throws {
    let state = try parse(single(defaultCredits: credits(hasCredits: false)))

    XCTAssertEqual(try XCTUnwrap(state.codexCredits).amount, .noneAvailable)
  }

  func testAmountsPreserveSignedFractionalBalancesAndZeroMeaning() throws {
    let fractional = try parse(single(defaultCredits: credits(balance: "-3.1234567890")))
    XCTAssertEqual(
      try XCTUnwrap(fractional.codexCredits).amount,
      .balance(decimal("-3.1234567890"))
    )

    let explicitZero = try parse(single(defaultCredits: credits(balance: "0", hasCredits: false)))
    XCTAssertEqual(try XCTUnwrap(explicitZero.codexCredits).amount, .balance(.zero))

    let noCredits = try parse(single(defaultCredits: credits(hasCredits: false)))
    XCTAssertEqual(try XCTUnwrap(noCredits.codexCredits).amount, .noneAvailable)
  }

  func testUnlimitedAndAvailableCreditAmountsRemainDistinct() throws {
    let unlimited = try parse(single(defaultCredits: credits(unlimited: true)))
    XCTAssertEqual(try XCTUnwrap(unlimited.codexCredits).amount, .unlimited)

    let available = try parse(single(defaultCredits: credits()))
    XCTAssertEqual(try XCTUnwrap(available.codexCredits).amount, .available)
  }

  func testMalformedBalanceIsNotConvertedToZero() throws {
    for invalid in ["not-a-number", "-", ".", "12bad"] {
      let state = try parse(single(defaultCredits: credits(balance: invalid)))
      XCTAssertNil(state.codexCredits, invalid)
    }
  }

  func testCreditOnlySnapshotCanConnectWithoutUsageWindows() throws {
    let state = try parse(
      root(defaultCredits: credits(balance: "12345.6789"), includeWindow: false)
    )

    XCTAssertEqual(state.status, .connected)
    XCTAssertTrue(state.metrics.isEmpty)
    XCTAssertNil(state.summary)
    XCTAssertEqual(
      try XCTUnwrap(state.codexCredits).amount,
      .balance(decimal("12345.6789"))
    )
  }

  func testSparkOnlyNotificationPreservesDefaultCredits() throws {
    let initial = try parse(
      root(defaultCredits: credits(balance: "12345.6789"))
    )
    let update = CodexUsageParser.parseNotification(
      params: root(defaultCredits: nil, sparkCredits: credits(balance: "7.25")),
      merging: initial,
      now: now.addingTimeInterval(60)
    )

    XCTAssertEqual(update?.codexCredits, initial.codexCredits)
    XCTAssertEqual(update?.codexSparkMetrics.count, 1)
  }

  func testCreditNotificationPreservesOmittedAndExplicitNullCredits() throws {
    let initial = try parse(single(defaultCredits: credits(balance: "12345.6789")))

    let omitted = CodexUsageParser.parseNotification(
      params: .object(["rateLimits": snapshot()]),
      merging: initial,
      now: now.addingTimeInterval(60)
    )
    XCTAssertEqual(omitted?.codexCredits, initial.codexCredits)

    let explicitNull = CodexUsageParser.parseNotification(
      params: .object(["rateLimits": snapshot(credits: .null)]),
      merging: initial,
      now: now.addingTimeInterval(60)
    )
    XCTAssertEqual(explicitNull?.codexCredits, initial.codexCredits)

    let explicitZero = CodexUsageParser.parseNotification(
      params: .object([
        "rateLimits": snapshot(credits: credits(balance: "0"))
      ]),
      merging: initial,
      now: now.addingTimeInterval(60)
    )
    XCTAssertEqual(explicitZero?.codexCredits?.amount, .balance(.zero))
  }

  func testFullReadWithExplicitNullCreditsClearsPreviousValue() throws {
    let initial = try parse(single(defaultCredits: credits(balance: "12345.6789")))
    XCTAssertNotNil(initial.codexCredits)

    let cleared = try parse(single(defaultCredits: .null))
    XCTAssertNil(cleared.codexCredits)
  }

  func testCreditExpiryOnlyUsesCreditExpiryField() throws {
    let resetExpiry = 1_799_000_000.0
    let state = try parse(
      root(
        defaultCredits: credits(balance: "12345.6789"),
        resetsAt: 1_799_100_000,
        resetCredits: .object([
          "availableCount": .number(1),
          "credits": .array([
            .object([
              "status": .string("available"),
              "expiresAt": .number(resetExpiry),
            ])
          ]),
        ])
      )
    )

    XCTAssertNil(state.codexCredits?.expiresAt)
    XCTAssertEqual(state.metrics.first?.resetsAt, Date(timeIntervalSince1970: 1_799_100_000))
    XCTAssertEqual(
      state.resetCredits?.earliestKnownExpiry,
      Date(timeIntervalSince1970: resetExpiry)
    )
  }

  func testCreditOnlyTransientFailureKeepsStaleBalance() throws {
    let initial = try parse(
      root(defaultCredits: credits(balance: "12345.6789"), includeWindow: false)
    )
    let stale = initial.handlingFailure(URLError(.notConnectedToInternet))

    XCTAssertEqual(stale.status, .stale)
    XCTAssertEqual(stale.codexCredits, initial.codexCredits)
  }

  func testCreditBalanceRoundTripsAndHardFailureClearsIt() throws {
    var initial = try parse(single(defaultCredits: credits(balance: "12345.6789")))
    initial.codexCreditGrant = CodexCreditGrant(amount: 450, expiresOn: "2032-04-15")
    let encoded = try JSONEncoder().encode(initial)
    XCTAssertEqual(try JSONDecoder().decode(ProviderUsageState.self, from: encoded), initial)

    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    legacy.removeValue(forKey: "codexCredits")
    legacy.removeValue(forKey: "codexCreditGrant")
    XCTAssertNil(
      try JSONDecoder().decode(
        ProviderUsageState.self,
        from: JSONSerialization.data(withJSONObject: legacy)
      ).codexCredits
    )

    let failed = initial.failed(message: "Offline", recoverySuggestion: "Retry")
    XCTAssertNil(failed.codexCredits)
    XCTAssertNil(failed.codexCreditGrant)
  }

  private func decimal(_ value: String) -> Decimal {
    Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
  }

  private func credits(
    balance: String? = nil,
    hasCredits: Bool = true,
    unlimited: Bool = false,
    expiresAt: Double? = nil
  ) -> JSONValue {
    var object: [String: JSONValue] = [
      "hasCredits": .bool(hasCredits),
      "unlimited": .bool(unlimited),
    ]
    if let balance { object["balance"] = .string(balance) }
    if let expiresAt { object["expiresAt"] = .number(expiresAt) }
    return .object(object)
  }

  private func snapshot(
    limitID: String = "codex",
    credits: JSONValue? = nil,
    includeWindow: Bool = true,
    resetsAt: Double? = nil
  ) -> JSONValue {
    var object: [String: JSONValue] = ["limitId": .string(limitID)]
    if includeWindow {
      var primary: [String: JSONValue] = [
        "usedPercent": .number(20),
        "windowDurationMins": .number(300),
      ]
      if let resetsAt { primary["resetsAt"] = .number(resetsAt) }
      object["primary"] = .object(primary)
    }
    if let credits { object["credits"] = credits }
    return .object(object)
  }

  private func root(
    defaultCredits: JSONValue?,
    sparkCredits: JSONValue? = nil,
    includeWindow: Bool = true,
    resetsAt: Double? = nil,
    resetCredits: JSONValue? = nil
  ) -> JSONValue {
    var byLimitID: [String: JSONValue] = [:]
    if let defaultCredits {
      byLimitID["codex"] = snapshot(
        credits: defaultCredits,
        includeWindow: includeWindow,
        resetsAt: resetsAt
      )
    }
    if let sparkCredits {
      byLimitID["codex_bengalfox"] = snapshot(
        limitID: "codex_bengalfox",
        credits: sparkCredits,
        includeWindow: includeWindow
      )
    }
    var object: [String: JSONValue] = [
      "rateLimitsByLimitId": .object(byLimitID)
    ]
    if let resetCredits { object["rateLimitResetCredits"] = resetCredits }
    return .object(object)
  }

  private func single(defaultCredits: JSONValue?, includeWindow: Bool = true) -> JSONValue {
    .object([
      "rateLimits": snapshot(credits: defaultCredits, includeWindow: includeWindow)
    ])
  }

  private func parse(_ result: JSONValue) throws -> ProviderUsageState {
    try CodexUsageParser.parse(result: result, now: now)
  }
}
