import SwiftUI

@main
struct AIUsageMonitorApp: App {
  @NSApplicationDelegateAdaptor(AIUsageMonitorAppDelegate.self)
  private var appDelegate

  var body: some Scene {
    Settings {
      SettingsView()
        .environmentObject(appDelegate.model)
    }
  }
}

@MainActor
final class AIUsageMonitorAppDelegate: NSObject, NSApplicationDelegate {
  let model = AppModel()
  private var statusBarController: StatusBarController?
  private var terminationTask: Task<Void, Never>?

  func applicationDidFinishLaunching(_ notification: Notification) {
    statusBarController = StatusBarController(model: model)
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard terminationTask == nil else { return .terminateLater }
    terminationTask = Task { @MainActor [weak self, weak sender] in
      guard let self, let sender else { return }
      await model.shutdown()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
