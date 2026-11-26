import AppKit
import XCTest

@testable import AIUsageMonitor

@MainActor
final class StatusPanelDismissalTests: XCTestCase {
  func testDismissedPanelCannotBeRestoredBySystemOrdering() {
    _ = NSApplication.shared
    let panel = PersistentStatusPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 400),
      styleMask: [.borderless], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    defer { panel.close() }
    panel.beginUserPresentation()
    panel.orderFront(nil)
    XCTAssertTrue(panel.isVisible)
    panel.orderOut(nil)
    panel.orderFrontRegardless()
    panel.orderFront(nil)
    panel.makeKeyAndOrderFront(nil)
    XCTAssertFalse(panel.isVisible, "System restoration must not open a dismissed usage panel")
  }

  func testMenuPanelUsesExplicitDismissalAndCannotJoinFullScreenSpaces() {
    let panel = NSPanel()
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    WindowPresentationPolicy.menuPanel.apply(to: panel)
    XCTAssertFalse(panel.hidesOnDeactivate)
    XCTAssertEqual(panel.level, .normal)
    XCTAssertFalse(panel.collectionBehavior.contains(.canJoinAllSpaces))
    XCTAssertFalse(panel.collectionBehavior.contains(.fullScreenAuxiliary))
  }

  func testLosingFocusClosesPanelAndBackgroundResizeDoesNotReopenIt() {
    _ = NSApplication.shared
    let panel = PersistentStatusPanel(
      contentRect: NSRect(x: 0, y: 0, width: 350, height: 400),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    defer { panel.close() }
    panel.beginUserPresentation()
    panel.orderFront(nil)
    XCTAssertTrue(panel.isVisible)

    panel.resignKey()
    XCTAssertFalse(panel.isVisible, "Leaving the usage panel must dismiss it")

    panel.setContentSize(NSSize(width: 350, height: 500))
    panel.setFrameOrigin(NSPoint(x: 100, y: 100))
    XCTAssertFalse(panel.isVisible, "Background layout must keep the panel dismissed")
  }
}
