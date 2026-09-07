import XCTest

@testable import AIUsageMonitor

final class CodexResetCreditsTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_788_800_000)
  private let window: JSONValue = .object([
    "limitId": .string("codex"),
    "primary": .object([
      "usedPercent": .number(20), "windowDurationMins": .number(300),
    ]),
  ])

  func testRealResponseShapePreservesCountAndSortsExpiryDetails() throws {
    let state = try parse(
      #"{"availableCount":3,"credits":[{"id":"unused-id","status":"available","expiresAt":1791173939},{"status":"available","expiresAt":1789948935},{"status":"available","expiresAt":1791079853}]}"#
    )
    let credits = try XCTUnwrap(state.resetCredits)
    XCTAssertEqual(credits.availableCount, 3)
    XCTAssertEqual(
      credits.sortedCredits.compactMap(\.expiresAt).map(\.timeIntervalSince1970),
      [1_789_948_935, 1_791_079_853, 1_791_173_939])
    XCTAssertEqual(credits.earliestKnownExpiry, Date(timeIntervalSince1970: 1_789_948_935))
    XCTAssertTrue(credits.hasCompleteExpiryDetails)
    XCTAssertEqual(credits.updatedAt, now)
    XCTAssertEqual(state.defaultSummary, .availablePercent(80))
  }

  func testCountIsAuthoritativeWhenDetailsAreCappedOrMissing() throws {
    for json in [
      #"{"availableCount":3,"credits":null}"#,
      #"{"availableCount":3}"#,
      #"{"availableCount":3,"credits":[]}"#,
      #"{"availableCount":3,"credits":[{"status":"available","expiresAt":1791173939}]}"#,
    ] {
      let credits = try XCTUnwrap(parse(json).resetCredits)
      XCTAssertEqual(credits.availableCount, 3)
      XCTAssertFalse(credits.hasCompleteExpiryDetails)
    }
  }

  func testZeroIsDifferentFromUnavailableAndInvalidCounts() throws {
    XCTAssertEqual(try parse(#"{"availableCount":0,"credits":[]}"#).resetCredits?.availableCount, 0)
    for json in [
      "null", "{}", #"{"availableCount":-1}"#, #"{"availableCount":1.5}"#,
      #"{"availableCount":1e100}"#, #"{"availableCount":"3"}"#,
    ] {
      XCTAssertNil(try parse(json).resetCredits)
    }
    XCTAssertNil(try CodexUsageParser.parse(result: .object(["rateLimits": window])).resetCredits)
  }

  func testUnknownExpiryIsKeptAndNonAvailableDetailsAreExcluded() throws {
    let credits = try XCTUnwrap(
      parse(
        #"{"availableCount":2,"credits":[{"status":"available","expiresAt":null},{"status":"expired","expiresAt":1},{"status":"consumed","expiresAt":2},{"status":"available","expiresAt":1791173939}]}"#
      ).resetCredits)
    XCTAssertEqual(credits.sortedCredits.count, 2)
    XCTAssertNotNil(credits.sortedCredits.first?.expiresAt)
    XCTAssertNil(credits.sortedCredits.last?.expiresAt)
    XCTAssertFalse(credits.hasCompleteExpiryDetails)
  }

  func testWindowNotificationPreservesResetCreditsAndTheirOriginalTimestamp() throws {
    let initial = try parse(#"{"availableCount":3,"credits":null}"#)
    let updated = CodexUsageParser.parseNotification(
      params: .object(["rateLimits": window]), merging: initial,
      now: now.addingTimeInterval(60)
    )
    XCTAssertEqual(updated?.resetCredits, initial.resetCredits)
    XCTAssertEqual(updated?.updatedAt, now.addingTimeInterval(60))
  }

  func testNotificationsReplaceResetCreditsAndExplicitNullClearsThem() throws {
    let initial = try parse(#"{"availableCount":3,"credits":null}"#)
    for includeWindow in [true, false] {
      var params: [String: JSONValue] = [
        "rateLimitResetCredits": .object(["availableCount": .number(2)])
      ]
      if includeWindow { params["rateLimits"] = window }
      let updated = CodexUsageParser.parseNotification(
        params: .object(params), merging: initial, now: now.addingTimeInterval(60))
      XCTAssertEqual(updated?.resetCredits?.availableCount, 2)
      XCTAssertEqual(updated?.resetCredits?.updatedAt, now.addingTimeInterval(60))
      XCTAssertEqual(updated?.metrics, initial.metrics)
      params["rateLimitResetCredits"] = .null
      XCTAssertNil(
        CodexUsageParser.parseNotification(params: .object(params), merging: initial)?.resetCredits)
    }
  }

  func testFullRefreshWithoutCreditsDoesNotReuseOldCredits() throws {
    XCTAssertNotNil(try parse(#"{"availableCount":3}"#).resetCredits)
    XCTAssertNil(try CodexUsageParser.parse(result: .object(["rateLimits": window])).resetCredits)
  }

  func testCacheRoundTripAndLegacyCacheWithoutNewField() throws {
    let initial = try parse(
      #"{"availableCount":3,"credits":[{"status":"available","expiresAt":1791173939}]}"#)
    let encoded = try JSONEncoder().encode(initial)
    XCTAssertEqual(try JSONDecoder().decode(ProviderUsageState.self, from: encoded), initial)
    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    legacy.removeValue(forKey: "resetCredits")
    let decoded = try JSONDecoder().decode(
      ProviderUsageState.self,
      from: JSONSerialization.data(withJSONObject: legacy))
    XCTAssertNil(decoded.resetCredits)
    XCTAssertEqual(decoded.metrics, initial.metrics)
  }

  func testProviderFailureClearsResetCredits() throws {
    let initial = try parse(#"{"availableCount":3}"#)
    let failed = initial.failed(message: "Offline", recoverySuggestion: "Retry")
    XCTAssertNil(failed.resetCredits)
  }

  private func parse(_ json: String) throws -> ProviderUsageState {
    try CodexUsageParser.parse(
      result: .object([
        "rateLimits": window,
        "rateLimitResetCredits": JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)),
      ]), now: now)
  }
}
