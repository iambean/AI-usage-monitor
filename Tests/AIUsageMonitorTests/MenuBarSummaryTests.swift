import XCTest

@testable import AIUsageMonitor

final class MenuBarSummaryTests: XCTestCase {
  func testCodexMenuBarUsesOnlyDefaultLimitAndNeverSpark() {
    let state = ProviderUsageState(
      id: .codex,
      name: "Codex",
      symbolName: "c.circle.fill",
      status: .connected,
      summary: .availablePercent(100),
      metrics: [
        UsageMetric(
          id: "codex_bengalfox.primary",
          label: "Spark · 5 hours",
          value: .availablePercent(100),
          resetsAt: nil,
          resetDescription: nil,
          period: .fiveHour
        ),
        UsageMetric(
          id: "codex.secondary",
          label: "Cycle",
          value: .availablePercent(5),
          resetsAt: nil,
          resetDescription: nil,
          period: .weekly
        ),
      ],
      updatedAt: nil,
      message: nil
    )

    XCTAssertEqual(MenuBarSummary.displayText(for: state), "5%")
  }

  func testOnlyUsesTheFirstEnabledProviderDefaultValue() {
    let codex = ProviderUsageState(
      id: .codex,
      name: "Codex",
      symbolName: "c.circle.fill",
      status: .connected,
      summary: .availablePercent(72),
      metrics: [
        UsageMetric(
          id: "codex.secondary",
          label: "Cycle",
          value: .availablePercent(72),
          resetsAt: nil,
          resetDescription: nil,
          period: .weekly
        )
      ],
      updatedAt: nil,
      message: nil
    )
    let deepSeek = ProviderUsageState(
      id: .deepseek,
      name: "DeepSeek",
      symbolName: "d.circle.fill",
      status: .connected,
      summary: .balance(110, currency: "CNY"),
      metrics: [],
      updatedAt: nil,
      message: nil
    )

    XCTAssertEqual(MenuBarSummary.displayText(for: [codex, deepSeek]), "72%")
    XCTAssertEqual(MenuBarSummary.displayText(for: [deepSeek, codex]), "¥110.00")
    XCTAssertEqual(MenuBarSummary.displayText(for: deepSeek), "¥110.00")
  }

  func testFormatsResetAsAnAbsoluteDateAndTime() {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(identifier: "Asia/Shanghai")
    components.year = 2026
    components.month = 8
    components.day = 2
    components.hour = 15
    components.minute = 30
    let date = components.date!

    let text = UsageResetFormatter.dateTime(
      for: date,
      locale: Locale(identifier: "zh-Hans-CN"),
      timeZone: TimeZone(identifier: "Asia/Shanghai")!
    )

    XCTAssertTrue(text.contains("8月2日"))
    XCTAssertTrue(text.contains("15:30"))
  }

  func testLegacyCachedMetricsStillPreferFiveHourUsage() throws {
    let data = Data(
      """
      {
        "id": "kimi",
        "name": "Kimi Code",
        "symbolName": "moon.circle.fill",
        "status": "connected",
        "summary": {
          "kind": "availablePercent",
          "value": 37,
          "total": 100,
          "unit": "%",
          "currency": null
        },
        "metrics": [
          {
            "id": "kimi.period",
            "label": "周期",
            "value": {
              "kind": "availablePercent",
              "value": 37,
              "total": 100,
              "unit": "%",
              "currency": null
            },
            "resetsAt": null,
            "resetDescription": null
          },
          {
            "id": "kimi.300.TIME_UNIT_MINUTE",
            "label": "5 小时",
            "value": {
              "kind": "availablePercent",
              "value": 75,
              "total": 100,
              "unit": "%",
              "currency": null
            },
            "resetsAt": null,
            "resetDescription": null
          }
        ],
        "updatedAt": null,
        "message": null
      }
      """.utf8
    )

    let state = try JSONDecoder().decode(ProviderUsageState.self, from: data)

    XCTAssertEqual(state.defaultSummary, .availablePercent(75))
    XCTAssertEqual(
      state.displayMetrics.map(\.id),
      [
        "kimi.300.TIME_UNIT_MINUTE",
        "kimi.period",
      ]
    )
  }
}
