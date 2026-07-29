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

    XCTAssertEqual(state.summary, .availablePercent(100))
    XCTAssertEqual(state.metrics.map(\.label), ["周期", "5 小时"])
    XCTAssertEqual(state.metrics.map(\.value.value), [59, 100])
  }

  func testParsesKimiLimitWhenUsedIsMissing() throws {
    let data = Data(
      """
      {
        "usage": {
          "limit": "100",
          "used": "29",
          "remaining": "71",
          "resetTime": "2026-08-01T00:00:00Z"
        },
        "limits": [{
          "window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"},
          "detail": {
            "limit": "100",
            "remaining": "100",
            "resetTime": "2026-07-28T15:00:00Z"
          }
        }]
      }
      """.utf8
    )

    let state = try KimiUsageParser.parse(data)

    XCTAssertEqual(state.summary, .availablePercent(100))
    XCTAssertEqual(state.metrics.map(\.label), ["周期", "5 小时"])
    XCTAssertEqual(state.metrics.map(\.value.value), [71, 100])
  }

  func testParsesKimiExhaustedLimitWhenRemainingIsMissing() throws {
    let data = Data(
      """
      {
        "usage": {
          "limit": "100",
          "used": "78",
          "remaining": "22",
          "resetTime": "2026-07-31T23:29:17.285992Z"
        },
        "limits": [{
          "window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"},
          "detail": {
            "limit": "100",
            "used": "100",
            "resetTime": "2026-07-28T06:29:17.285992Z"
          }
        }]
      }
      """.utf8
    )

    let state = try KimiUsageParser.parse(data)

    XCTAssertEqual(state.summary, .availablePercent(0))
    XCTAssertEqual(state.metrics.map(\.value.value), [22, 0])
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

    XCTAssertEqual(state.summary, .availablePercent(72.5))
    XCTAssertEqual(state.metrics.map(\.value.value), [72.5, 41])
  }

  func testParsesCurrentMiniMaxTokenPlanCountsAsUsedValues() throws {
    let data = Data(
      """
      {
        "base_resp": {"status_code": 0, "status_msg": "success"},
        "model_remains": [{
          "model_name": "MiniMax-M2.7",
          "end_time": 2000000000000,
          "current_interval_total_count": 1500,
          "current_interval_usage_count": 228,
          "current_weekly_total_count": 15000,
          "current_weekly_usage_count": 780,
          "current_weekly_status": 1,
          "weekly_end_time": 2000100000000
        }]
      }
      """.utf8
    )

    let state = try MiniMaxUsageParser.parse(data)

    XCTAssertEqual(state.metrics.map(\.value.value), [84.8, 94.8])
    XCTAssertEqual(state.summary, .availablePercent(84.8))
  }

  func testParsesUnlimitedMiniMaxWeeklyQuota() throws {
    let data = Data(
      """
      {
        "base_resp": {"status_code": 0, "status_msg": "success"},
        "model_remains": [{
          "model_name": "MiniMax-M2.7",
          "current_interval_total_count": 1500,
          "current_interval_usage_count": 0,
          "current_weekly_total_count": 0,
          "current_weekly_usage_count": 0,
          "current_weekly_status": 3
        }]
      }
      """.utf8
    )

    let state = try MiniMaxUsageParser.parse(data)

    XCTAssertEqual(state.metrics.map(\.value), [.availablePercent(100), .unlimited])
    XCTAssertEqual(state.metrics.last?.value.displayText, "∞")
  }

  func testUsesCurrentMiniMaxTokenPlanEndpoints() {
    XCTAssertEqual(
      MiniMaxUsageProviderFactory.endpoint(for: .global).absoluteString,
      "https://api.minimax.io/v1/token_plan/remains"
    )
    XCTAssertEqual(
      MiniMaxUsageProviderFactory.endpoint(for: .china).absoluteString,
      "https://api.minimaxi.com/v1/token_plan/remains"
    )
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

  func testParsesCursorTeamSpendAndMemberCount() throws {
    let data = Data(
      """
      {
        "teamMemberSpend": [
          {
            "spendCents": 1250,
            "fastPremiumRequests": 20,
            "name": "A",
            "email": "a@example.com",
            "role": "owner",
            "hardLimitOverrideDollars": 100
          },
          {
            "spendCents": 250,
            "fastPremiumRequests": 5,
            "name": "B",
            "email": "b@example.com",
            "role": "member",
            "hardLimitOverrideDollars": 0
          }
        ],
        "subscriptionCycleStart": 1782864000000,
        "totalMembers": 2,
        "totalPages": 1
      }
      """.utf8
    )

    let page = try CursorUsageParser.parsePage(data)
    let state = try CursorUsageParser.makeState(
      pages: [page],
      now: Date(timeIntervalSince1970: 1_000)
    )

    XCTAssertEqual(page.spendCents, 1500)
    XCTAssertEqual(page.totalMembers, 2)
    XCTAssertEqual(state.summary, .spent(15, currency: "USD"))
    XCTAssertEqual(state.summary?.displayText, "$15.00")
    XCTAssertEqual(state.summary?.caption, "已用")
    XCTAssertEqual(state.metrics.last?.value.displayText, "2 人")
    XCTAssertEqual(
      CursorUsageProviderFactory.endpoint.absoluteString,
      "https://api.cursor.com/teams/spend"
    )
  }

  func testAggregatesCursorSpendAcrossPages() throws {
    let state = try CursorUsageParser.makeState(
      pages: [
        CursorTeamSpendPage(
          spendCents: 1_000,
          subscriptionCycleStart: nil,
          totalMembers: 150,
          totalPages: 2
        ),
        CursorTeamSpendPage(
          spendCents: 500,
          subscriptionCycleStart: nil,
          totalMembers: 150,
          totalPages: 2
        ),
      ]
    )

    XCTAssertEqual(state.summary, .spent(15, currency: "USD"))
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

    XCTAssertEqual(state.summary, .availablePercent(76))
    XCTAssertEqual(state.metrics.map(\.value.value), [76, 39])
    XCTAssertEqual(
      state.metrics.first?.resetsAt,
      Date(timeIntervalSince1970: 2_000_000_000)
    )
  }
}
