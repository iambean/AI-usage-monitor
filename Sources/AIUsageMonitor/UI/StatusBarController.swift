import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
  private let model: AppModel
  let statusItem: NSStatusItem
  let panel: PersistentStatusPanel
  private let hostingController: NSHostingController<AnyView>
  private let panelSizing = MenuPanelSizing()
  private var cancellables: Set<AnyCancellable> = []
  private var outsideClickMonitor: Any?
  private var localClickMonitor: Any?

  init(
    model: AppModel,
    notifications: NotificationCenter = .default,
    workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter
  ) {
    self.model = model
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    hostingController = NSHostingController(rootView: AnyView(EmptyView()))
    panel = PersistentStatusPanel(
      contentRect: NSRect(x: 0, y: 0, width: 350, height: 1),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    super.init()

    hostingController.rootView = AnyView(
      SizedMenuPanel(
        sizing: panelSizing, model: model,
        onContentHeightChange: { [weak self] _ in
          DispatchQueue.main.async { [weak self] in
            self?.resizeAndPositionPanel()
          }
        })
    )

    configureStatusItem()
    configurePanel()
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
      MainActor.assumeIsolated { self?.panel.orderOut(nil) }
    }
    localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      MainActor.assumeIsolated {
        if let self, event.window !== self.panel,
          event.window !== self.statusItem.button?.window {
          self.panel.orderOut(nil)
        }
      }
      return event
    }
    observeModel(notifications: notifications, workspaceNotifications: workspaceNotifications)
    model.startIfNeeded()
  }

  deinit {
    if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
    NSStatusBar.system.removeStatusItem(statusItem)
  }

  @objc
  func togglePanel() {
    if panel.isVisible {
      panel.orderOut(nil)
    } else {
      showPanel()
    }
  }

  @objc
  private func statusItemClicked() {
    if panel.isVisible {
      panel.orderOut(nil)
      return
    }
    let revision = panel.presentationRevision
    DispatchQueue.main.async { [weak self] in
      guard let self, self.panel.presentationRevision == revision,
        !self.panel.isVisible else { return }
      self.showPanel()
    }
  }

  private func configureStatusItem() {
    guard let button = statusItem.button else { return }
    button.target = self
    button.action = #selector(statusItemClicked)
    button.sendAction(on: [.leftMouseUp])
    button.imagePosition = .imageLeading
    button.imageScaling = .scaleProportionallyDown
    updateStatusItem()
  }

  private func configurePanel() {
    panel.contentViewController = hostingController
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isMovable = false
    panel.isReleasedWhenClosed = false
    panel.animationBehavior = .utilityWindow
    panel.becomesKeyOnlyIfNeeded = false
    WindowPresentationPolicy.menuPanel.apply(to: panel)

    hostingController.view.wantsLayer = true
    hostingController.view.layer?.cornerRadius = 16
    hostingController.view.layer?.cornerCurve = .continuous
    hostingController.view.layer?.masksToBounds = true
  }

  private func observeModel(
    notifications: NotificationCenter, workspaceNotifications: NotificationCenter
  ) {
    // A nonactivating panel may already belong to an inactive app, so observing
    // NSApplication deactivation alone misses switching apps and full-screen Spaces.
    for name in [NSWorkspace.activeSpaceDidChangeNotification,
      NSWorkspace.willSleepNotification] {
      workspaceNotifications.publisher(for: name)
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.panel.orderOut(nil) }
        .store(in: &cancellables)
    }
    workspaceNotifications.publisher(for: NSWorkspace.didActivateApplicationNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] notification in
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
          as? NSRunningApplication,
          app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        self?.panel.orderOut(nil)
      }
      .store(in: &cancellables)
    notifications.publisher(for: NSApplication.didResignActiveNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.panel.orderOut(nil) }
      .store(in: &cancellables)
    notifications.publisher(for: NSApplication.didChangeScreenParametersNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.resizeAndPositionPanel() }
      .store(in: &cancellables)
    notifications.publisher(for: NSWindow.didChangeScreenNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] notification in
        guard let self, let window = notification.object as? NSWindow,
          window === self.statusItem.button?.window || window === self.panel
        else { return }
        self.resizeAndPositionPanel()
      }
      .store(in: &cancellables)
    notifications.publisher(for: .aiUsageOpenPanel)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.showPanel() }
      .store(in: &cancellables)
    model.$preferences
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.updateStatusItem()
        self?.resizeAndPositionPanel()
      }
      .store(in: &cancellables)
    model.$providerStates
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.updateStatusItem()
        self?.resizeAndPositionPanel()
      }
      .store(in: &cancellables)

    model.$appLanguage
      .dropFirst()
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.updateStatusItem()
        self?.resizeAndPositionPanel()
      }
      .store(in: &cancellables)
  }

  private func updateStatusItem() {
    guard let button = statusItem.button else { return }
    button.image = NSImage(
      systemSymbolName: model.primaryState.symbolName,
      accessibilityDescription: model.primaryState.name
    )
    button.image?.isTemplate = true
    let state = model.primaryState
    let selectedID = model.preferences.selectedMetrics[state.id.rawValue]
    let metric = state.selectedMetric(selectedID)
    button.title = " " + (metric?.value.compactDisplayText ?? "—")
    button.toolTip =
      metric.map { UsagePresentation.caption($0, providerID: state.id) }
      ?? L10n.text("monitor.windowUnavailable", "窗口暂不可用")
  }

  private func showPanel() {
    model.panelDidOpen()
    resizeAndPositionPanel(force: true)
    WindowPresentationPolicy.menuPanel.apply(to: panel)
    panel.beginUserPresentation()
    // This path is reached only by an explicit user click or notification action.
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    panel.orderFrontRegardless()
  }

  private func resizeAndPositionPanel(force: Bool = false) {
    // Hidden windows must not be moved by polling or screen-change callbacks.
    guard force || panel.isVisible else { return }
    guard let button = statusItem.button, let statusWindow = button.window,
      let screen = statusWindow.screen ?? panel.screen ?? NSScreen.main
    else { return }
    let anchor = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
    let geometry = MenuPanelGeometry(anchor: anchor, visibleFrame: screen.visibleFrame)
    if panelSizing.maximumHeight != geometry.maximumHeight {
      panelSizing.maximumHeight = geometry.maximumHeight
    }
    hostingController.view.layoutSubtreeIfNeeded()
    let frame = geometry.frame(contentHeight: hostingController.view.fittingSize.height)
    // Avoid generating another screen-change notification for an unchanged frame.
    if panel.frame != frame {
      panel.setFrame(frame, display: panel.isVisible)
    }
  }

}

final class PersistentStatusPanel: NSPanel {
  private(set) var presentationRevision: UInt64 = 0
  private var userPresentationAllowed = false

  func beginUserPresentation() {
    userPresentationAllowed = true
    DiagnosticLog.record("panel_user_open")
  }

  override func orderOut(_ sender: Any?) {
    presentationRevision &+= 1
    userPresentationAllowed = false
    super.orderOut(sender)
  }

  override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    if place == .out {
      presentationRevision &+= 1
      userPresentationAllowed = false
    }
    guard place == .out || userPresentationAllowed else {
      DiagnosticLog.record("panel_restore_blocked")
      return
    }
    super.order(place, relativeTo: otherWin)
  }

  override func orderFrontRegardless() {
    guard userPresentationAllowed else {
      DiagnosticLog.record("panel_restore_blocked")
      return
    }
    super.orderFrontRegardless()
  }

  override func makeKeyAndOrderFront(_ sender: Any?) {
    guard userPresentationAllowed else { return }
    super.makeKeyAndOrderFront(sender)
  }

  override func cancelOperation(_ sender: Any?) {
    orderOut(sender)
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func resignKey() {
    super.resignKey()
    // Order out explicitly so later application activation cannot restore this panel.
    orderOut(nil)
  }
}

private struct SizedMenuPanel: View {
  @ObservedObject var sizing: MenuPanelSizing
  let model: AppModel
  let onContentHeightChange: (CGFloat) -> Void
  var body: some View {
    MenuBarContentView(
      maximumHeight: sizing.maximumHeight, onContentHeightChange: onContentHeightChange
    )
    .environmentObject(model)
  }
}
