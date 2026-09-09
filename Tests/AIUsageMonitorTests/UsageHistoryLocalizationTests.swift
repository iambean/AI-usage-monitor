import AppKit
import SwiftUI
import XCTest

@testable import AIUsageMonitor

final class UsageHistoryLocalizationTests: XCTestCase {
  func testMixedLanguageHistoryUsesCurrentLanguageWithoutChangingSamples() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let history = ["Spark · 5 小时", "Spark · 5 hours"].enumerated().map { index, label in
      UsageHistoryPoint(
        providerID: .codex, metricID: "codex_bengalfox.primary", metricLabel: label,
        recordedAt: now.addingTimeInterval(Double(index - 2)), value: Double(90 - index),
        scale: .percent, unit: "%", accountScope: "account")
    }
    for (language, title) in [
      (AppLanguage.english, "Spark · 5 hours"), (.simplifiedChinese, "Spark · 5 小时"),
    ] {
      let snapshot = UsageTrendQuery(
        history: history, providerID: .codex, duration: 86400,
        currentAccountScope: "account", now: now, language: language
      ).projection()
      XCTAssertEqual(snapshot.chartData.points.map(\.metricLabel), [title, title])
      XCTAssertEqual(snapshot.windows.last?.title, title)
      XCTAssertEqual(snapshot.chartData.points.map(\.id), history.map(\.id))
      XCTAssertEqual(snapshot.chartData.points.map(\.seriesID), history.map(\.seriesID))
      XCTAssertEqual(snapshot.chartData.points.map(\.value), history.map(\.value))
      XCTAssertEqual(snapshot.chartData.points.map(\.recordedAt), history.map(\.recordedAt))
    }
    XCTAssertEqual(history.first?.metricLabel, "Spark · 5 小时")
  }

  @MainActor
  func testEnglishTrendProjectionInNativeView() async throws {
    _ = NSApplication.shared
    let previous = AppLanguageStore.load()
    AppLanguageStore.save(.english)
    defer { AppLanguageStore.save(previous) }
    let now = Date()
    let history = (0..<20).map { index in
      UsageHistoryPoint(
        providerID: .codex, metricID: "codex.primary", metricLabel: "周期",
        recordedAt: now.addingTimeInterval(Double(index - 20) * 3600), value: Double(100 - index),
        scale: .percent, unit: "%")
    }
    let model = AppModel(
      previewStates: [.loading(.codex)], previewHistory: history, previewLanguage: .english)
    var projection = UsageTrendProjection.empty
    let host = NSHostingView(
      rootView: UsageTrendView(onProjectionChange: { projection = $0 }).environmentObject(model))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 850, height: 650), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(nanoseconds: 100_000_000)
    host.layoutSubtreeIfNeeded()
    XCTAssertEqual(Set(projection.chartData.points.map(\.metricLabel)), ["Cycle"])
    XCTAssertEqual(projection.chartData.points.count, history.count)
  }

  func testKnownProviderLabelsAndDurationsTranslateBothWays() {
    let english = UsageHistoryLocalization(language: .english)
    let chinese = UsageHistoryLocalization(language: .simplifiedChinese)
    let labels = [
      ("周期", "Cycle"), ("Spark · 周期", "Spark · Cycle"),
      ("12 小时", "12 hours"), ("30 分钟", "30 minutes"), ("2 天", "2 days"),
      ("CNY 可用余额", "CNY available balance"), ("API 可用余额", "Available API balance"),
      ("本周期团队支出", "Team spend this cycle"), ("团队成员", "Team members"),
      ("套餐额度", "Plan quota"), ("团队共享", "Team shared"), ("资源包", "Resource package"),
    ]
    for (zh, en) in labels {
      XCTAssertEqual(english.label(zh), en)
      XCTAssertEqual(chinese.label(en), zh)
    }
    XCTAssertEqual(english.label("Custom model · Custom window"), "Custom model · Custom window")
  }
}
