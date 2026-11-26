import Foundation
import XCTest

@testable import AIUsageMonitor

final class CodexCreditGrantTests: XCTestCase {
  private let accountKey = "account-key"
  private var now: Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar.date(from: DateComponents(year: 2032, month: 2, day: 29, hour: 12))!
  }

  func testReadsMatchingGrantAndKeepsItAvailableOnExpiryDate() throws {
    let url = try write([accountKey: CodexCreditGrant(amount: 7_200, expiresOn: "2032-02-29")])

    let grant = CodexCreditGrantStore.grant(
      for: accountKey,
      now: now,
      fileURL: url
    )

    XCTAssertEqual(grant?.amount, 7_200)
    XCTAssertEqual(grant?.expiresOn, "2032-02-29")
  }

  func testUnknownAccountOrExpiredGrantIsUnavailable() throws {
    let url = try write([accountKey: CodexCreditGrant(amount: 7_200, expiresOn: "2032-02-29")])

    XCTAssertNil(CodexCreditGrantStore.grant(for: "other", now: now, fileURL: url))
    XCTAssertNil(
      CodexCreditGrantStore.grant(
        for: accountKey,
        now: now.addingTimeInterval(86_400),
        fileURL: url
      )
    )
  }

  func testInvalidAmountAndDateAreRejected() throws {
    let values = [
      accountKey: CodexCreditGrant(amount: 0, expiresOn: "2032-02-29"),
      "bad-date": CodexCreditGrant(amount: 10, expiresOn: "2032-02-30"),
      "bad-year-sign": CodexCreditGrant(amount: 10, expiresOn: "+032-02-29"),
      "bad-month-sign": CodexCreditGrant(amount: 10, expiresOn: "2032-+2-29"),
      "bad-day-sign": CodexCreditGrant(amount: 10, expiresOn: "2032-02-+9"),
    ]
    let url = try write(values)

    XCTAssertNil(CodexCreditGrantStore.grant(for: accountKey, now: now, fileURL: url))
    XCTAssertNil(CodexCreditGrantStore.grant(for: "bad-date", now: now, fileURL: url))
    XCTAssertNil(CodexCreditGrantStore.grant(for: "bad-year-sign", now: now, fileURL: url))
    XCTAssertNil(CodexCreditGrantStore.grant(for: "bad-month-sign", now: now, fileURL: url))
    XCTAssertNil(CodexCreditGrantStore.grant(for: "bad-day-sign", now: now, fileURL: url))
  }

  func testExpiryDateHasNoFabricatedTimeComponent() throws {
    let url = try write([accountKey: CodexCreditGrant(amount: 7_200, expiresOn: "2032-02-29")])
    let grant = try XCTUnwrap(
      CodexCreditGrantStore.grant(for: accountKey, now: now, fileURL: url)
    )

    XCTAssertEqual(grant.expiresOn, "2032-02-29")
    XCTAssertEqual(grant.displayExpiry(locale: Locale(identifier: "en_US")), "Feb 29, 2032")
    XCTAssertEqual(grant, CodexCreditGrant(amount: 7_200, expiresOn: "2032-02-29"))
  }

  func testExpirationUsesGregorianLocalCivilDate() throws {
    let grant = CodexCreditGrant(amount: 10, expiresOn: "2032-02-29")
    let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 60 * 60))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone

    let expiryDay = try XCTUnwrap(calendar.date(from: DateComponents(
      year: 2032, month: 2, day: 29, hour: 23, minute: 59)))
    let nextDay = try XCTUnwrap(calendar.date(from: DateComponents(
      year: 2032, month: 3, day: 1, hour: 0, minute: 1)))

    XCTAssertFalse(grant.isExpired(on: expiryDay, calendar: calendar))
    XCTAssertTrue(grant.isExpired(on: nextDay, calendar: calendar))
  }

  func testMalformedOtherAccountDoesNotHideValidGrant() throws {
    let data: [String: Any] = [
      accountKey: ["amount": 7_200, "expiresOn": "2032-02-29"],
      "other": ["amount": "invalid", "expiresOn": "not-a-date"],
    ]
    let url = try writeFixture(JSONSerialization.data(withJSONObject: data))

    XCTAssertEqual(
      CodexCreditGrantStore.grant(for: accountKey, now: now, fileURL: url)?.amount,
      7_200
    )
    XCTAssertNil(CodexCreditGrantStore.grant(for: "other", now: now, fileURL: url))
  }

  private func write(_ grants: [String: CodexCreditGrant]) throws -> URL {
    try writeFixture(JSONEncoder().encode(grants))
  }

  private func writeFixture(_ data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try data.write(to: url)
    addTeardownBlock { try FileManager.default.removeItem(at: url) }
    return url
  }
}
