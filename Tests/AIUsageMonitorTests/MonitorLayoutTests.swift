import AppKit
import SwiftUI
import XCTest

@testable import AIUsageMonitor

final class MonitorLayoutTests: XCTestCase {
  @MainActor
  func testMenuAndSettingsFitTheirNativeWindows() async throws {
    let model = AppModel(previewStates: states)
    var reportedHeight: CGFloat = 0
    let menu = try await capture(
      MenuBarContentView(onContentHeightChange: { height in
        if height > 1 { reportedHeight = height }
      }).environmentObject(model), width: 350, height: 680, name: "optimized-menu")
    XCTAssertEqual(reportedHeight, menu.height, accuracy: 1)
    XCTAssertEqual(menu.width, 350, accuracy: 1)
    XCTAssertLessThanOrEqual(menu.height, 680)
    XCTAssertGreaterThan(menu.height, 300, "Menu must render provider rows on first presentation")
    let settings = try await capture(
      SettingsView().environmentObject(model), width: 620, height: 660, name: "optimized-settings")
    XCTAssertEqual(settings.width, 620, accuracy: 1)
    XCTAssertEqual(settings.height, 660, accuracy: 1)
  }

  @MainActor
  func testCollapsedProvidersShrinkTheMeasuredPanel() async throws {
    let model = AppModel(previewStates: states)
    model.updatePreferences { $0.collapsedProviders = states.map(\.id) }
    let size = try await capture(
      MenuBarContentView().environmentObject(model), width: 350, height: 680,
      name: "optimized-collapsed")
    XCTAssertGreaterThan(size.height, 180)
    XCTAssertLessThan(size.height, 400)
  }

  @MainActor
  func testReminderAndDataSettingsRenderWithoutNetworkOrPermissionRequests() async throws {
    let model = AppModel(previewStates: states)
    _ = try await capture(
      ScrollView { MonitorNotificationSettingsView().environmentObject(model) },
      width: 596, height: 620, name: "optimized-reminders")
    _ = try await capture(
      ScrollView { MonitorGeneralSettingsView().environmentObject(model) },
      width: 596, height: 620, name: "optimized-data-settings")
    XCTAssertFalse(model.preferences.notificationsEnabled)
  }

  @MainActor
  func testTrendRendersWindowSelectorAndHistoryGap() async throws {
    let start = Date().addingTimeInterval(-25_000)
    let points = [0, 3_600, 7_200, 18_000, 21_600, 25_000].enumerated().map { index, seconds in
      UsageHistoryPoint(
        providerID: .codex, metricID: "codex.primary", metricLabel: "Default · 周",
        recordedAt: start.addingTimeInterval(Double(seconds)), value: Double(100 - index * 7),
        scale: .percent, unit: "%")
    }
    let model = AppModel(previewStates: states, previewHistory: points)
    _ = try await capture(
      UsageTrendView().environmentObject(model), width: 700, height: 650, name: "optimized-trend")
  }

  @MainActor
  func testManyProvidersAreScrollableInsteadOfPushingFooterOffscreen() async throws {
    let model = AppModel(
      previewStates: states + [make(.claude, 35), make(.minimax, 20), make(.qoder, 10)])
    let size = try await capture(
      MenuBarContentView(maximumHeight: 680).environmentObject(model), width: 350, height: 680,
      name: "optimized-many-providers")
    XCTAssertLessThanOrEqual(size.height, 680)
  }

  @MainActor
  private func capture<V: View>(_ content: V, width: CGFloat, height: CGFloat, name: String)
    async throws -> NSSize
  {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: width, height: height),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)
    let host = NSHostingView(rootView: content.background(Color(nsColor: .windowBackgroundColor)))
    window.contentView = host
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    host.layoutSubtreeIfNeeded()
    window.orderFront(nil)
    try await Task.sleep(nanoseconds: 120_000_000)
    host.layoutSubtreeIfNeeded()
    let fitting = host.fittingSize
    XCTAssertGreaterThan(fitting.width, 0)
    if let path = ProcessInfo.processInfo.environment["AI_USAGE_QA_OUTPUT"] {
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      try png.write(to: URL(fileURLWithPath: path).appendingPathComponent(name + ".png"))
    }
    window.close()
    return fitting
  }

  private var states: [ProviderUsageState] {
    var codex = make(.codex, 100)
    codex.accountLabel = "pe•••@example.com · Pro"
    codex.metrics = [
      UsageMetric(
        id: "codex.primary", label: "周", value: .availablePercent(100),
        resetsAt: Date().addingTimeInterval(7 * 86_400), resetDescription: nil, period: .weekly),
      UsageMetric(
        id: "codex_bengalfox.primary", label: "Spark · 5小时", value: .availablePercent(50),
        resetsAt: Date().addingTimeInterval(7_200), resetDescription: nil, period: .fiveHour),
      UsageMetric(
        id: "codex_bengalfox.secondary", label: "Spark · 周", value: .availablePercent(63),
        resetsAt: Date().addingTimeInterval(4 * 86_400), resetDescription: nil, period: .weekly),
    ]
    codex.resetCredits = CodexResetCredits(
      availableCount: 3,
      credits: [CodexResetCredit(expiresAt: Date().addingTimeInterval(14 * 86_400))],
      updatedAt: .now)
    var deepseek = make(.deepseek, 100)
    deepseek.metrics = [
      UsageMetric(
        id: "balance", label: "CNY", value: .balance(23.12, currency: "CNY"), resetsAt: nil,
        resetDescription: nil)
    ]
    return [codex, make(.kimi, 79), deepseek]
  }
  private func make(_ id: ProviderID, _ value: Double) -> ProviderUsageState {
    let meta = ProviderCatalog.metadata(for: id)
    return ProviderUsageState(
      id: id, name: meta.name, symbolName: meta.symbolName, status: .connected,
      summary: .availablePercent(value),
      metrics: [
        UsageMetric(
          id: id.rawValue + ".primary", label: "5小时", value: .availablePercent(value),
          resetsAt: Date().addingTimeInterval(3_600), resetDescription: nil, period: .fiveHour)
      ],
      updatedAt: .now, message: nil)
  }
}
