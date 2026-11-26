import AppKit
import XCTest

@testable import AIUsageMonitor

@MainActor
final class StatusBarControllerTests: XCTestCase {
  private var model: AppModel!
  private var controller: StatusBarController!
  private var notifications: NotificationCenter!
  private var workspaceNotifications: NotificationCenter!

  override func setUp() async throws {
    _ = NSApplication.shared
    model = AppModel(previewStates: [.loading(.codex)])
    notifications = NotificationCenter()
    workspaceNotifications = NotificationCenter()
    controller = StatusBarController(
      model: model, notifications: notifications, workspaceNotifications: workspaceNotifications)
    await settle()
  }

  override func tearDown() async throws {
    controller.panel.orderOut(nil)
    controller = nil
    model = nil
    notifications = nil
    workspaceNotifications = nil
  }

  func testStartupAndBackgroundUpdatesNeverOpenPanel() async {
    XCTAssertFalse(controller.panel.isVisible)
    for index in 0..<20 {
      model.updatePreferences { $0.compact = index.isMultiple(of: 2) }
      notifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
      await settle()
      XCTAssertFalse(controller.panel.isVisible)
    }
  }

  func testHiddenPanelPositionIsUntouchedByBackgroundLayoutEvents() async {
    let parkedFrame = NSRect(x: 123, y: 234, width: 350, height: 200)
    controller.panel.setFrame(parkedFrame, display: false)
    model.updatePreferences { $0.compact.toggle() }
    notifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    notifications.post(name: NSWindow.didChangeScreenNotification, object: controller.panel)
    await settle()
    XCTAssertEqual(controller.panel.frame.origin, parkedFrame.origin)
    XCTAssertFalse(controller.panel.isVisible)
  }

  func testDismissalCancelsPendingStatusButtonOpen() async throws {
    let button = try XCTUnwrap(controller.statusItem.button)
    button.performClick(nil)
    controller.panel.orderOut(nil)
    await settle()
    XCTAssertFalse(controller.panel.isVisible)
    button.performClick(nil)
    await settle()
    XCTAssertTrue(controller.panel.isVisible)
  }

  func testSystemRestoreAfterSpaceSwitchCannotReopenPanel() async {
    controller.togglePanel()
    workspaceNotifications.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    await settle()
    for _ in 0..<20 {
      controller.panel.orderFrontRegardless()
      controller.panel.makeKeyAndOrderFront(nil)
      model.updatePreferences { $0.compact.toggle() }
      await settle()
      XCTAssertFalse(controller.panel.isVisible)
    }
    controller.togglePanel()
    await settle()
    XCTAssertTrue(controller.panel.isVisible)
  }

  func testStatusButtonActionOpensClosesAndReopensPanel() async throws {
    XCTAssertFalse(controller.panel.styleMask.contains(.nonactivatingPanel))
    let button = try XCTUnwrap(controller.statusItem.button)
    button.performClick(nil)
    await settle()
    XCTAssertTrue(controller.panel.isVisible)
    button.performClick(nil)
    await settle()
    XCTAssertFalse(controller.panel.isVisible)
    button.performClick(nil)
    await settle()
    XCTAssertTrue(controller.panel.isVisible)
  }

  func testStatusItemToggleStillOpensClosesAndReopensPanel() async {
    controller.togglePanel()
    await settle()
    XCTAssertTrue(controller.panel.isVisible)
    XCTAssertGreaterThan(controller.panel.frame.height, 50)
    controller.togglePanel()
    XCTAssertFalse(controller.panel.isVisible)
    controller.togglePanel()
    await settle()
    XCTAssertTrue(controller.panel.isVisible)
  }

  func testSpaceSwitchSleepAndDeactivationDismissPanelWithoutReopening() async {
    for (center, name) in [
      (workspaceNotifications!, NSWorkspace.activeSpaceDidChangeNotification),
      (workspaceNotifications!, NSWorkspace.willSleepNotification),
      (notifications!, NSApplication.didResignActiveNotification),
    ] {
      controller.togglePanel()
      await settle()
      XCTAssertTrue(controller.panel.isVisible, "Before \(name)")
      center.post(name: name, object: nil)
      await settle()
      XCTAssertFalse(controller.panel.isVisible, "After \(name)")
      model.updatePreferences { $0.compact.toggle() }
      workspaceNotifications.post(name: NSWorkspace.didWakeNotification, object: nil)
      notifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
      await settle()
      XCTAssertFalse(controller.panel.isVisible, "Must remain dismissed after \(name)")
    }
  }

  func testOtherApplicationActivationClosesPanelButOwnActivationDoesNot() async throws {
    let other = try XCTUnwrap(NSWorkspace.shared.runningApplications.first {
      $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
    })
    controller.togglePanel()
    await settle()
    workspaceNotifications.post(
      name: NSWorkspace.didActivateApplicationNotification, object: nil,
      userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
    await settle()
    XCTAssertTrue(controller.panel.isVisible)
    workspaceNotifications.post(
      name: NSWorkspace.didActivateApplicationNotification, object: nil,
      userInfo: [NSWorkspace.applicationUserInfoKey: other])
    await settle()
    XCTAssertFalse(controller.panel.isVisible)
  }

  func testUserNotificationActionStillOpensPanelAndVisibleRefreshKeepsItOpen() async {
    notifications.post(name: .aiUsageOpenPanel, object: nil)
    await settle()
    XCTAssertTrue(controller.panel.isVisible)
    model.updatePreferences { $0.compact.toggle() }
    await settle()
    XCTAssertTrue(controller.panel.isVisible)
  }

  func testSettingsAndTrendWindowsRemainAvailable() async throws {
    controller.togglePanel()
    await settle()
    SettingsWindowController.shared.show(model: model)
    await settle()
    let settings = try XCTUnwrap(SettingsWindowController.shared.window)
    XCTAssertTrue(settings.isVisible)
    settings.close()
    controller.panel.orderOut(nil)
    await settle()

    controller.togglePanel()
    await settle()
    UsageTrendWindowController.shared.show(model: model)
    await settle()
    let trend = try XCTUnwrap(UsageTrendWindowController.shared.window)
    XCTAssertTrue(trend.isVisible)
    trend.close()
  }

  private func settle() async {
    try? await Task.sleep(nanoseconds: 50_000_000)
  }
}
