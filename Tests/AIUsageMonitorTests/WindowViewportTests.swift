import AppKit
import SwiftUI
import XCTest

@testable import AIUsageMonitor

final class WindowViewportTests: XCTestCase {
  @MainActor
  func testMenuUsesAvailableScreenHeightWithoutAnArbitraryCap() async throws {
    let model = AppModel(previewStates: states)
    let (window, host) = mount(
      MenuBarContentView(maximumHeight: 1_400).environmentObject(model),
      size: NSSize(width: 350, height: 1_400))
    defer { window.close() }
    try await settle(host)
    XCTAssertGreaterThan(
      host.fittingSize.height, 680, "Tall screens should show the whole provider list")
    XCTAssertLessThanOrEqual(host.fittingSize.height, 1_400)
    let scroll = try XCTUnwrap(scrollViews(host).first)
    XCTAssertLessThanOrEqual(
      overflow(scroll), 1, "No provider should require scrolling while the menu fits the screen")
    XCTAssertFalse(scroll.hasVerticalScroller, "The indicator must be disabled when content fits")
  }

  @MainActor
  func testMenuReservesHeaderAndFooterInsideShortScreenBudget() async throws {
    let model = AppModel(previewStates: states)
    let (window, host) = mount(
      MenuBarContentView(maximumHeight: 500).environmentObject(model),
      size: NSSize(width: 350, height: 500))
    defer { window.close() }
    try await settle(host)
    XCTAssertLessThanOrEqual(
      host.fittingSize.height, 500.5, "The complete menu, including its footer, must fit")
    XCTAssertGreaterThan(overflow(try XCTUnwrap(scrollViews(host).first)), 1)
  }

  @MainActor
  func testTrendTitleAndFooterRemainReachableAfterNativeResizing() async throws {
    let now = Date()
    var points: [UsageHistoryPoint] = []
    for index in 0..<20 {
      let date = now.addingTimeInterval(Double(index - 20) * 600)
      let value = Double(100 - index)
      let scope: String? = index == 19 ? "current" : nil
      points.append(
        UsageHistoryPoint(
          providerID: .codex, metricID: "codex.primary", metricLabel: "Default · 周",
          recordedAt: date, value: value, scale: .percent, unit: "%", accountScope: scope))
    }
    let model = AppModel(previewStates: [states[0]], previewHistory: points)
    var titleBounds = CGRect.null
    var footerBounds = CGRect.null
    let (window, host) = mount(
      UsageTrendView(onViewportBoundsChange: { title, footer in
        titleBounds = title
        footerBounds = footer
      }).environmentObject(model), size: NSSize(width: 900, height: 800))
    defer { window.close() }
    for size in [
      NSSize(width: 900, height: 800), NSSize(width: 680, height: 600),
      NSSize(width: 740, height: 650),
    ] {
      window.setContentSize(size)
      try await settle(host)
      if let scroll = scrollViews(host).first {
        scrollToEdge(scroll, bottom: false)
        try await settle(host)
      }
      let titleBarHeight = window.frame.height - host.bounds.height
      let viewport = CGRect(
        x: 0, y: titleBarHeight, width: host.bounds.width, height: host.bounds.height)
      XCTAssertFalse(titleBounds.isNull)
      XCTAssertTrue(
        viewport.insetBy(dx: -1, dy: -1).contains(titleBounds),
        "Title clipped at \(size): \(titleBounds), viewport \(viewport)")
      if let scroll = scrollViews(host).first, overflow(scroll) > 1 {
        scrollToEdge(scroll, bottom: true)
        try await settle(host)
      }
      XCTAssertFalse(footerBounds.isNull)
      XCTAssertTrue(
        viewport.insetBy(dx: -1, dy: -1).contains(footerBounds),
        "Footer unreachable at \(size): \(footerBounds), viewport \(viewport)")
    }
  }

  @MainActor
  func testTrendMinimumHeightSurvivesHostingLayout() async throws {
    _ = NSApplication.shared
    let model = AppModel(previewStates: [states[0]])
    let controller = UsageTrendWindowController.shared
    controller.show(model: model)
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }
    try await Task.sleep(nanoseconds: 150_000_000)
    window.contentView?.layoutSubtreeIfNeeded()
    XCTAssertGreaterThanOrEqual(window.contentMinSize.height, 600)
    XCTAssertGreaterThanOrEqual(window.contentMinSize.width, 680)
    XCTAssertGreaterThanOrEqual(window.contentView?.fittingSize.height ?? 0, 600)
  }

  func testPanelGeometryUsesAnchorScreenAndKeepsItsBottomVisible() {
    let screen = NSRect(x: 1_920, y: -200, width: 1_920, height: 1_400)
    let layout = MenuPanelGeometry(
      anchor: NSRect(x: 3_700, y: 1_200, width: 60, height: 24), visibleFrame: screen)
    XCTAssertGreaterThan(layout.maximumHeight, 1_300)
    let tall = layout.frame(contentHeight: 2_000)
    XCTAssertEqual(tall.minY, screen.minY + 8)
    XCTAssertLessThan(tall.maxY, screen.maxY)
    XCTAssertTrue(screen.contains(tall))
    XCTAssertEqual(layout.frame(contentHeight: 700).height, 700)
  }

  @MainActor
  private func mount<V: View>(_ content: V, size: NSSize) -> (NSWindow, NSHostingView<some View>) {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = NSHostingView(rootView: content.background(Color(nsColor: .windowBackgroundColor)))
    window.contentView = host
    window.orderFront(nil)
    return (window, host)
  }

  @MainActor
  private func settle(_ view: NSView) async throws {
    try await Task.sleep(nanoseconds: 150_000_000)
    view.layoutSubtreeIfNeeded()
    view.window?.displayIfNeeded()
  }

  @MainActor
  private func scrollViews(_ view: NSView) -> [NSScrollView] {
    (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews($0) }
  }

  @MainActor
  private func overflow(_ scroll: NSScrollView) -> CGFloat {
    (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height
  }

  @MainActor
  private func scrollToEdge(_ scroll: NSScrollView, bottom: Bool) {
    guard let document = scroll.documentView else { return }
    let end = bottom == document.isFlipped
    let y = end ? document.bounds.maxY - 1 : document.bounds.minY
    document.scrollToVisible(NSRect(x: 0, y: y, width: 1, height: 1))
    scroll.reflectScrolledClipView(scroll.contentView)
  }

  private var states: [ProviderUsageState] {
    [ProviderID.codex, .claude, .kimi, .minimax, .qoder, .deepseek].map { id in
      let meta = ProviderCatalog.metadata(for: id)
      return ProviderUsageState(
        id: id, name: meta.name, symbolName: meta.symbolName, status: .connected,
        summary: .availablePercent(80),
        metrics: [
          UsageMetric(
            id: id.rawValue + ".primary", label: "5小时", value: .availablePercent(80),
            resetsAt: Date().addingTimeInterval(3_600), resetDescription: nil, period: .fiveHour),
          UsageMetric(
            id: id.rawValue + ".secondary", label: "周期", value: .availablePercent(65),
            resetsAt: Date().addingTimeInterval(86_400), resetDescription: nil, period: .weekly),
        ], updatedAt: .now, message: nil)
    }
  }
}
