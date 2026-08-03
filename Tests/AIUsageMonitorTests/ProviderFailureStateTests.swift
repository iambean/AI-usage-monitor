import XCTest

@testable import AIUsageMonitor

final class ProviderFailureStateTests: XCTestCase {
  func testFailureClearsCachedUsageAndKeepsActionableGuidance() {
    let connected = ProviderUsageState(
      id: .kimi,
      name: "Kimi Code",
      symbolName: "moon.circle.fill",
      status: .connected,
      summary: .availablePercent(35),
      metrics: [
        UsageMetric(
          id: "kimi.5h",
          label: "5 小时",
          value: .availablePercent(35),
          resetsAt: nil,
          resetDescription: nil,
          period: .fiveHour
        )
      ],
      updatedAt: Date(),
      message: "打开用量页面",
      messageAction: ProviderMessageAction(
        title: "查看",
        url: URL(string: "https://example.com/usage")!
      )
    )

    let failed = connected.failed(
      message: "服务返回了无法识别的数据",
      recoverySuggestion: "请在 Kimi Code 中运行 /usage 后重试"
    )

    XCTAssertEqual(failed.status, .error)
    XCTAssertNil(failed.summary)
    XCTAssertTrue(failed.metrics.isEmpty)
    XCTAssertNil(failed.updatedAt)
    XCTAssertEqual(failed.message, "服务返回了无法识别的数据")
    XCTAssertNil(failed.messageAction)
    XCTAssertEqual(
      failed.recoverySuggestion,
      "请在 Kimi Code 中运行 /usage 后重试"
    )
  }

  func testErrorStateNeverExposesLegacyCachedSummary() {
    let errorState = ProviderUsageState(
      id: .kimi,
      name: "Kimi Code",
      symbolName: "moon.circle.fill",
      status: .error,
      summary: .availablePercent(35),
      metrics: [
        UsageMetric(
          id: "kimi.5h",
          label: "5 小时",
          value: .availablePercent(35),
          resetsAt: nil,
          resetDescription: nil,
          period: .fiveHour
        )
      ],
      updatedAt: Date(),
      message: "数据读取失败"
    )

    XCTAssertNil(errorState.defaultSummary)
    XCTAssertEqual(MenuBarSummary.displayText(for: [errorState]), "—")
  }
}
