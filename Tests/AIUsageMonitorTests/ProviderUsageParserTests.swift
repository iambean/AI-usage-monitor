import Foundation
import XCTest

@testable import AIUsageMonitor

final class ProviderUsageParserTests: XCTestCase {
  func testParsesKimiNativeUsageWindows() throws {
    let data = Data(
      """
      {
        "usage": {
          "limit": "100",
          "used": "41",
          "remaining": "59",
          "resetTime": "2026-07-31T23:29:17.285992Z"
        },
        "limits": [{
          "window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"},
          "detail": {
            "limit": "100",
            "used": "0",
            "remaining": "100",
            "resetTime": "2026-07-27T15:29:17.285992Z"
          }
        }]
      }
      """.utf8
    )

    let state = try KimiUsageParser.parse(
      data,
      now: Date(timeIntervalSince1970: 1_000)
    )

    XCTAssertEqual(state.summary, .availablePercent(59))
    XCTAssertEqual(state.metrics.map(\.label), ["周期", "5 小时"])
    XCTAssertEqual(state.metrics.map(\.value.value), [59, 100])
  }

  func testParsesMiniMaxRemainingPercent() throws {
    let data = Data(
      """
      {
        "model_remains": [{
          "model_name": "general",
          "current_interval_remaining_percent": 72.5,
          "current_weekly_status": 1,
          "current_weekly_remaining_percent": 41,
          "end_time": 2000000000000,
          "weekly_end_time": 2000100000000
        }],
        "base_resp": {"status_code": 0, "status_msg": "ok"}
      }
      """.utf8
    )

    let state = try MiniMaxUsageParser.parse(data)

    XCTAssertEqual(state.summary, .availablePercent(41))
    XCTAssertEqual(state.metrics.map(\.value.value), [72.5, 41])
  }

  func testParsesDeepSeekBalanceWithoutInventingPercent() throws {
    let data = Data(
      """
      {
        "is_available": true,
        "balance_infos": [{
          "currency": "CNY",
          "total_balance": "110.00",
          "granted_balance": "10.00",
          "topped_up_balance": "100.00"
        }]
      }
      """.utf8
    )

    let state = try DeepSeekUsageParser.parse(data)

    XCTAssertEqual(state.summary, .balance(110, currency: "CNY"))
    XCTAssertNil(state.summary?.availableFraction)
    XCTAssertEqual(state.summary?.displayText, "¥110.00")
  }

  func testParsesQoderCredits() throws {
    let data = Data(
      """
      {
        "planQuota": {
          "quotaSummary": {"usedValue": 350.5, "limitValue": 1000, "unit": "credits"}
        },
        "totalQuota": {
          "quotaSummary": {"usedValue": 450.5, "limitValue": 1500, "unit": "credits"}
        },
        "nextResetAt": "2026-04-01T00:00:00Z",
        "status": "active"
      }
      """.utf8
    )

    let state = try QoderUsageParser.parse(data)

    XCTAssertEqual(state.summary, .used(450.5, of: 1500, unit: "credits"))
    XCTAssertEqual(state.summary?.caption, "已用")
    XCTAssertEqual(state.metrics.first?.label, "总额度")
  }

  func testParsesClaudeStatusLineWithEpochResetTime() throws {
    let data = Data(
      """
      {
        "rate_limits": {
          "five_hour": {
            "used_percentage": 24,
            "resets_at": 2000000000
          },
          "seven_day": {
            "used_percentage": 61,
            "resets_at": "2033-05-19T03:33:20Z"
          }
        }
      }
      """.utf8
    )

    let state = try ClaudeUsageParser.parse(data)

    XCTAssertEqual(state.summary, .availablePercent(39))
    XCTAssertEqual(state.metrics.map(\.value.value), [76, 39])
    XCTAssertEqual(
      state.metrics.first?.resetsAt,
      Date(timeIntervalSince1970: 2_000_000_000)
    )
  }
}
