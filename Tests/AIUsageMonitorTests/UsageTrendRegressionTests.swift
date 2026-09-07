import AppKit
import SwiftUI
import XCTest

@testable import AIUsageMonitor

final class UsageTrendRegressionTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  func testAddingAccountMetadataDoesNotHideLegacyQuotaHistory() {
    let history = (0..<100).map { point($0) } + [point(100, scope: "current")]
    let query = UsageTrendQuery(
      history: history, providerID: .codex, duration: 30 * 86_400,
      currentAccountScope: "current", now: now)
    let chart = query.chartData()
    XCTAssertEqual(
      chart.points.count, 101,
      "Default chart must still include untagged historical samples after upgrading")
    XCTAssertEqual(chart.points.filter { $0.accountScope == nil }.count, 100)
  }

  func testRangeRebuildHasBoundedCostWithHistory() {
    let history = (0..<1_000).map { point($0) } + [point(1_000, scope: "current")]
    let started = Date()
    let query = UsageTrendQuery(
      history: history, providerID: .codex, duration: 30 * 86_400,
      currentAccountScope: "current", now: now)
    _ = query.chartData()
    let elapsed = Date().timeIntervalSince(started)
    print("Trend query: \(history.count) samples, \(elapsed) seconds")
    XCTAssertLessThan(
      elapsed, 0.5, "Switching a time range must not regroup the entire history for every sample")
  }

  func testAllWindowsOverviewRetainsLegacyAndKnownSourcesWithoutRewritingThem() {
    let first = point(999)
    let other = UsageHistoryPoint(
      providerID: .codex, metricID: "codex.primary", metricLabel: "Default",
      recordedAt: first.recordedAt, value: 98, scale: .percent, unit: "%")
    let history = [first, other, point(1_000, scope: "current")]
    let query = UsageTrendQuery(
      history: history, providerID: .codex, duration: 86_400,
      currentAccountScope: "current", now: now)
    let snapshot = query.projection()
    XCTAssertEqual(snapshot.selectedWindowID, UsageTrendWindowOption.all)
    XCTAssertEqual(snapshot.chartData.points.count, 3)
    XCTAssertEqual(snapshot.chartData.windowLatestPoints.count, 2)
    XCTAssertTrue(snapshot.includesLegacy)
    XCTAssertEqual(snapshot.chartData.points.filter { $0.accountScope == nil }.count, 2)
    XCTAssertEqual(query.projection(selectedAccountID: "current").chartData.points.count, 1)
    XCTAssertEqual(
      query.projection(selectedAccountID: UsageTrendAccountOption.legacy).chartData.points.count, 2)
  }

  func testWindowChoicesStayStableAcrossRangesWithAnEmptySelectedWindow() {
    let old = UsageHistoryPoint(
      providerID: .codex, metricID: "old", metricLabel: "Old",
      recordedAt: now.addingTimeInterval(-3 * 86_400), value: 50, scale: .percent, unit: "%")
    let history = [old, point(1_000, scope: "current")]
    let day = UsageTrendQuery(
      history: history, providerID: .codex, duration: 86_400,
      currentAccountScope: "current", now: now)
    let month = UsageTrendQuery(
      history: history, providerID: .codex, duration: 30 * 86_400,
      currentAccountScope: "current", now: now)
    let selected = UsageTrendQuery.windowID(old)
    XCTAssertEqual(day.windows, month.windows)
    XCTAssertEqual(day.projection(selectedWindowID: selected).selectedWindowID, selected)
    XCTAssertTrue(day.projection(selectedWindowID: selected).chartData.points.isEmpty)
    XCTAssertEqual(month.projection(selectedWindowID: selected).chartData.points.count, 1)
  }

  @MainActor
  func testNativeTimeRangeSwitchingWithFullHistory() async throws {
    let history = try fullHistory()
    let codexPoints = history.filter { $0.providerID == .codex }
    let scope = codexPoints.last { $0.accountScope != nil }?.accountScope
    let latest = Dictionary(grouping: codexPoints, by: \.metricID).values.compactMap { points in
      points.max { $0.recordedAt < $1.recordedAt }
    }
    let state = ProviderUsageState(
      id: .codex, name: "Codex", symbolName: "c.circle.fill",
      status: .connected, summary: .availablePercent(98),
      metrics: latest.map {
        UsageMetric(
          id: $0.metricID, label: $0.metricLabel, value: .availablePercent($0.value),
          resetsAt: nil, resetDescription: nil)
      }, updatedAt: .now, message: nil, accountScope: scope)
    let model = AppModel(previewStates: [state], previewHistory: history)
    var projection = UsageTrendProjection.empty
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 740, height: 650),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)
    let host = NSHostingView(
      rootView: UsageTrendView(onProjectionChange: { projection = $0 })
        .environmentObject(model).background(Color(nsColor: .windowBackgroundColor)))
    window.contentView = host
    window.orderFront(nil)
    defer { window.close() }
    try await Task.sleep(nanoseconds: 150_000_000)
    host.layoutSubtreeIfNeeded()
    let control = try XCTUnwrap(segmentControls(in: host).first { $0.segmentCount == 3 })
    let durations: [TimeInterval] = [86_400, 7 * 86_400, 30 * 86_400]
    var worst: TimeInterval = 0
    for index in [0, 1, 2, 0, 1, 2] {
      let started = Date()
      control.selectedSegment = index
      XCTAssertTrue(control.sendAction(control.action, to: control.target))
      try await Task.sleep(nanoseconds: 50_000_000)
      host.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
      let completed = Date()
      let elapsed = completed.timeIntervalSince(started)
      worst = max(worst, elapsed)
      let beforeCount = codexPoints.filter {
        $0.recordedAt >= started.addingTimeInterval(-durations[index])
      }.count
      let afterCount = codexPoints.filter {
        $0.recordedAt >= completed.addingTimeInterval(-durations[index])
      }.count
      XCTAssertGreaterThanOrEqual(projection.chartData.points.count, afterCount)
      XCTAssertLessThanOrEqual(projection.chartData.points.count, beforeCount)
      XCTAssertGreaterThan(
        projection.chartData.points.count, 3, "A range change must not hide legacy history")
      XCTAssertLessThan(
        elapsed, 1.0, "Native range switching must remain responsive with full history")
      print(
        "Native range \(index): \(projection.chartData.points.count) samples, \(elapsed) seconds")
    }
    print("Native worst: \(worst) seconds; source history: \(history.count) records")
    if let path = ProcessInfo.processInfo.environment["AI_USAGE_QA_OUTPUT"] {
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      try png.write(to: URL(fileURLWithPath: path).appendingPathComponent("repaired-trend-30d.png"))
    }
  }

  @MainActor
  private func segmentControls(in view: NSView) -> [NSSegmentedControl] {
    (view as? NSSegmentedControl).map { [$0] } ?? view.subviews.flatMap { segmentControls(in: $0) }
  }

  private func fullHistory() throws -> [UsageHistoryPoint] {
    if let path = ProcessInfo.processInfo.environment["AI_USAGE_HISTORY_FIXTURE"] {
      return try JSONDecoder().decode(
        [UsageHistoryPoint].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }
    let reference = Date().addingTimeInterval(-10)
    return (0..<9_000).map { index in
      let metricIDs = ["codex.primary", "codex_bengalfox.primary", "codex_bengalfox.secondary"]
      return UsageHistoryPoint(
        providerID: .codex, metricID: metricIDs[index % 3],
        metricLabel: ["Default", "Spark · 5小时", "Spark · 周"][index % 3],
        recordedAt: reference.addingTimeInterval(Double(index - 8_999) * 240),
        value: Double(100 - index % 90), scale: .percent, unit: "%",
        accountScope: index >= 8_997 ? "current" : nil)
    }
  }

  func testHoverShowsOneLatestValuePerWindowAcrossUpgrade() {
    let oldTime = now.addingTimeInterval(-1_800)
    let old = [
      hoverPoint("default", 98, at: oldTime), hoverPoint("spark5h", 91, at: oldTime),
      hoverPoint("sparkWeek", 56, at: oldTime),
    ]
    let new = [
      hoverPoint("default", 97, at: now, scope: "current"),
      hoverPoint("spark5h", 91, at: now, scope: "current"),
      hoverPoint("sparkWeek", 56, at: now, scope: "current"),
    ]
    let chart = UsageTrendChartData(points: old + new)
    let values = chart.values(at: now)
    XCTAssertEqual(
      values.count, 3, "Tooltip must not show both legacy and tagged values for the same window")
    XCTAssertEqual(values.first { $0.metricID == "default" }?.value, 97)
    XCTAssertEqual(Set(values.map(UsageTrendQuery.windowID)).count, values.count)
    XCTAssertEqual(
      chart.points.count, 6, "Deduplicating the tooltip must not delete historical samples")
  }

  func testHoverBeforeUpgradeKeepsTheHistoricalValue() {
    let old = hoverPoint("default", 98, at: now.addingTimeInterval(-1_800))
    let new = hoverPoint("default", 97, at: now, scope: "current")
    XCTAssertEqual(
      UsageTrendChartData(points: [old, new]).values(at: now.addingTimeInterval(-60)), [old])
  }

  func testHoverEqualTimestampsPreferTaggedSample() {
    let old = hoverPoint("default", 98, at: now)
    let new = hoverPoint("default", 97, at: now, scope: "current")
    for points in [[old, new], [new, old]] {
      XCTAssertEqual(UsageTrendChartData(points: points).values(at: now), [new])
    }
  }

  private func hoverPoint(_ metricID: String, _ value: Double, at date: Date, scope: String? = nil)
    -> UsageHistoryPoint
  {
    UsageHistoryPoint(
      providerID: .codex, metricID: metricID, metricLabel: metricID,
      recordedAt: date, value: value, scale: .percent, unit: "%", accountScope: scope)
  }

  private func point(_ index: Int, scope: String? = nil) -> UsageHistoryPoint {
    UsageHistoryPoint(
      providerID: .codex, metricID: "codex_bengalfox.primary", metricLabel: "Spark · 5小时",
      recordedAt: now.addingTimeInterval(Double(index - 1_000) * 60),
      value: Double(100 - index % 100),
      scale: .percent, unit: "%", accountScope: scope)
  }
}
