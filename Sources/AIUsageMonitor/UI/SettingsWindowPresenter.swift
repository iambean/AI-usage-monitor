import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
  static let shared = SettingsWindowController()

  func show(model: AppModel) {
    let preferredScreen = NSApp.keyWindow?.screen ?? screenContainingMouse
    let settingsWindow = window ?? makeWindow(model: model, screen: preferredScreen)
    updateLocalization()
    WindowPresentationPolicy.natural.apply(to: settingsWindow)
    showWindow(nil)
    settingsWindow.makeKeyAndOrderFront(nil)
    settingsWindow.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
  }

  func updateLocalization() {
    window?.title = L10n.text("settings.windowTitle", "AI Usage 设置")
  }

  private func makeWindow(model: AppModel, screen: NSScreen?) -> NSWindow {
    let rootView = AnyView(
      SettingsView()
        .environmentObject(model)
    )
    let hostingController = NSHostingController(rootView: rootView)
    let settingsWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 540),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    settingsWindow.title = L10n.text("settings.windowTitle", "AI Usage 设置")
    settingsWindow.contentViewController = hostingController
    settingsWindow.delegate = self
    settingsWindow.isReleasedWhenClosed = false

    hostingController.view.layoutSubtreeIfNeeded()
    let fittingSize = hostingController.view.fittingSize
    if fittingSize.width > 0, fittingSize.height > 0 {
      settingsWindow.setContentSize(fittingSize)
    }
    center(settingsWindow, on: screen)

    window = settingsWindow
    return settingsWindow
  }

  private var screenContainingMouse: NSScreen? {
    let mouseLocation = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
      ?? NSScreen.main
  }

  private func center(_ window: NSWindow, on screen: NSScreen?) {
    guard let screen else {
      window.center()
      return
    }
    let visibleFrame = screen.visibleFrame
    let origin = NSPoint(
      x: visibleFrame.midX - window.frame.width / 2,
      y: visibleFrame.midY - window.frame.height / 2
    )
    window.setFrameOrigin(origin)
  }

  func windowWillClose(_ notification: Notification) {
    guard notification.object as? NSWindow === window else { return }
    window = nil
  }
}

@MainActor
struct SettingsWindowPresenter {
  typealias Action = @MainActor () -> Void
  typealias Scheduler = @MainActor (@escaping Action) -> Void

  let open: Action
  let schedule: Scheduler
  let focus: Action

  func present() {
    NSApp.activate(ignoringOtherApps: true)
    open()
    schedule(focus)
  }

  static func live(open: @escaping Action) -> Self {
    Self(
      open: open,
      schedule: { action in
        DispatchQueue.main.async {
          action()
        }
      },
      focus: {
        SettingsWindowFocus.focus()
      }
    )
  }
}

@MainActor
private enum SettingsWindowFocus {
  private static let maximumAttempts = 12
  private static let retryDelay: TimeInterval = 0.05

  static func focus(attempt: Int = 0) {
    NSApp.activate(ignoringOtherApps: true)
    guard let settingsWindow else {
      retryIfNeeded(after: attempt)
      return
    }
    WindowPresentationPolicy.natural.apply(to: settingsWindow)
    settingsWindow.makeKeyAndOrderFront(nil)
    settingsWindow.orderFrontRegardless()
    NSRunningApplication.current.activate(
      options: [.activateAllWindows, .activateIgnoringOtherApps]
    )
    NSApp.activate(ignoringOtherApps: true)
    guard NSApp.isActive, settingsWindow.isKeyWindow else {
      retryIfNeeded(after: attempt)
      return
    }
  }

  private static func retryIfNeeded(after attempt: Int) {
    guard attempt < maximumAttempts else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
      focus(attempt: attempt + 1)
    }
  }

  private static var settingsWindow: NSWindow? {
    NSApp.windows.first { window in
      window.isVisible
        && window.canBecomeKey
        && window.styleMask.contains(.titled)
    }
  }
}
