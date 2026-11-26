import AppKit
import SwiftUI
@testable import AIUsageMonitor

@MainActor
final class PanelAcceptance: NSObject, NSApplicationDelegate {
  private var controller: StatusBarController!
  private var model: AppModel!
  private var results: [[String: Any]] = []
  private var companionWindow: NSWindow?
  private let output = ProcessInfo.processInfo.environment["PANEL_ACCEPTANCE_OUTPUT"]
    ?? Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("results.json").path

  func applicationDidFinishLaunching(_ notification: Notification) {
    if ProcessInfo.processInfo.arguments.contains("--companion") {
      NSApp.setActivationPolicy(.regular)
      let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 300),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
      window.title = "Foreground companion for menu click test"
      companionWindow = window
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    model = AppModel(previewStates: [.loading(.codex), .loading(.kimi), .loading(.deepseek)])
    controller = StatusBarController(model: model)
    Task {
      if ProcessInfo.processInfo.arguments.contains("--background-click") {
        await checkBackgroundClick()
        NSApp.terminate(nil)
      } else {
        await runChecks()
      }
    }
  }

  private func check(_ name: String, _ passed: Bool) {
    results.append(["check": name, "passed": passed])
    let data = try! JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: URL(fileURLWithPath: output), options: .atomic)
  }

  private func settle(_ milliseconds: UInt64 = 200) async {
    try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
  }

  private func checkBackgroundClick() async {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    configuration.activates = true
    configuration.arguments = ["--companion"]
    let companion = try? await NSWorkspace.shared.openApplication(
      at: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Foreground Companion.app"), configuration: configuration)
    await settle(1_000)
    check("another app is active before status button click", !NSApp.isActive)
    controller.statusItem.button?.performClick(nil)
    await settle(700)
    check("status button opens visible panel from inactive app",
      controller.panel.isVisible && controller.panel.isOnActiveSpace
        && controller.panel.occlusionState.contains(.visible))
    controller.statusItem.button?.performClick(nil)
    await settle(700)
    check("second status button click closes panel", !controller.panel.isVisible)
    controller.statusItem.button?.performClick(nil)
    await settle(700)
    check("third status button click reopens panel", controller.panel.isVisible
      && controller.panel.isOnActiveSpace && controller.panel.occlusionState.contains(.visible))
    controller.panel.orderOut(nil)
    companion?.terminate()
  }

  private func runChecks() async {
    await settle()
    guard NSApp.isActive else {
      check("native focus precondition: run interactively with the test app in front", false)
      await checkBackgroundClick()
      check("all native checks completed", true)
      NSApp.terminate(nil)
      return
    }
    check("startup stays hidden", !controller.panel.isVisible)
    controller.togglePanel()
    await settle()
    check("manual open is visible and key", controller.panel.isVisible && controller.panel.isKeyWindow)
    for _ in 0..<20 { model.updatePreferences { $0.compact.toggle() }; await settle(10) }
    check("visible background updates preserve panel", controller.panel.isVisible)
    controller.togglePanel()
    await settle()
    check("second menu click closes", !controller.panel.isVisible)
    for _ in 0..<20 { model.updatePreferences { $0.compact.toggle() }; await settle(10) }
    check("hidden background updates do not reopen", !controller.panel.isVisible)

    controller.togglePanel()
    await settle()
    SettingsWindowPresenter.live { SettingsWindowController.shared.show(model: self.model) }.present()
    await settle(700)
    let settings = SettingsWindowController.shared.window
    check("settings opens and receives focus", settings?.isVisible == true && settings?.isKeyWindow == true)
    check("settings handoff dismisses panel", !controller.panel.isVisible)
    settings?.close()
    await settle()
    controller.togglePanel()
    await settle()
    UsageTrendWindowController.shared.show(model: model)
    await settle(700)
    let trend = UsageTrendWindowController.shared.window
    check("trend opens and receives focus", trend?.isVisible == true && trend?.isKeyWindow == true)
    check("trend handoff dismisses panel", !controller.panel.isVisible)
    trend?.close()
    await settle()

    let movie = NSWindow(
      contentRect: NSRect(x: 100, y: 100, width: 900, height: 600),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    movie.title = "AI Usage — Full-screen acceptance"
    movie.isReleasedWhenClosed = false
    movie.collectionBehavior = [.fullScreenPrimary]
    movie.backgroundColor = .black
    movie.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    await settle(400)
    controller.togglePanel()
    await settle()
    check("panel can open again before full-screen transition", controller.panel.isVisible)
    movie.toggleFullScreen(nil)
    for _ in 0..<60 {
      await settle(100)
      if movie.styleMask.contains(.fullScreen) { break }
    }
    await settle(700)
    check("native macOS full-screen entered", movie.styleMask.contains(.fullScreen))
    check("full-screen transition dismisses panel", !controller.panel.isVisible)
    for _ in 0..<20 { model.updatePreferences { $0.compact.toggle() }; await settle(50) }
    check("background updates during full-screen stay hidden", !controller.panel.isVisible)
    NSApp.activate(ignoringOtherApps: true)
    await settle()
    check("application reactivation does not restore panel", !controller.panel.isVisible)
    if movie.styleMask.contains(.fullScreen) { movie.toggleFullScreen(nil) }
    for _ in 0..<60 {
      await settle(100)
      if !movie.styleMask.contains(.fullScreen) { break }
    }
    await settle(700)
    check("exiting full-screen keeps panel hidden", !controller.panel.isVisible)
    movie.close()
    await settle()
    controller.togglePanel()
    await settle()
    check("manual reopen after full-screen still works", controller.panel.isVisible && controller.panel.isKeyWindow)
    controller.panel.orderOut(nil)
    await checkBackgroundClick()
    check("all native checks completed", true)
    NSApp.terminate(nil)
  }
}

@main
struct AcceptanceMain {
  @MainActor static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = PanelAcceptance()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
  }
}
