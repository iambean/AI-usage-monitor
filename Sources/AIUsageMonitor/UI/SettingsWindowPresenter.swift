import AppKit

@MainActor
struct SettingsWindowPresenter {
  typealias Action = @MainActor () -> Void
  typealias Scheduler = @MainActor (@escaping Action) -> Void

  let open: Action
  let schedule: Scheduler
  let focus: Action

  func present() {
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
  static func focus() {
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.makeKeyAndOrderFront(nil)
  }

  private static var settingsWindow: NSWindow? {
    NSApp.windows.first { window in
      window.isVisible
        && window.canBecomeKey
        && window.styleMask.contains(.titled)
    }
  }
}
