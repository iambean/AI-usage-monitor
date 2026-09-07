import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
  private let model: AppModel
  private let statusItem: NSStatusItem
  private let panel: PersistentStatusPanel
  private let hostingController: NSHostingController<AnyView>
  private let panelSizing = MenuPanelSizing()
  private var cancellables: Set<AnyCancellable> = []

  init(model: AppModel) {
    self.model = model
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    hostingController = NSHostingController(rootView: AnyView(EmptyView()))
    panel = PersistentStatusPanel(
      contentRect: NSRect(x: 0, y: 0, width: 350, height: 1),
      styleMask: [.borderless, .nonactivatingPanel],
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
    observeModel()
    model.startIfNeeded()
  }

  deinit {
    NSStatusBar.system.removeStatusItem(statusItem)
  }

  @objc
  private func togglePanel() {
    if panel.isVisible {
      panel.orderOut(nil)
    } else {
      showPanel()
    }
  }

  private func configureStatusItem() {
    guard let button = statusItem.button else { return }
    button.target = self
    button.action = #selector(togglePanel)
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
    WindowPresentationPolicy.natural.apply(to: panel)

    hostingController.view.wantsLayer = true
    hostingController.view.layer?.cornerRadius = 16
    hostingController.view.layer?.cornerCurve = .continuous
    hostingController.view.layer?.masksToBounds = true
  }

  private func observeModel() {
    NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.resizeAndPositionPanel() }
      .store(in: &cancellables)
    NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] notification in
        guard let self, let window = notification.object as? NSWindow,
          window === self.statusItem.button?.window || window === self.panel
        else { return }
        self.resizeAndPositionPanel()
      }
      .store(in: &cancellables)
    NotificationCenter.default.publisher(for: .aiUsageOpenPanel)
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
    resizeAndPositionPanel()
    WindowPresentationPolicy.natural.apply(to: panel)
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }

  private func resizeAndPositionPanel() {
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
    panel.setContentSize(frame.size)
    panel.setFrameOrigin(frame.origin)
  }

}

private final class PersistentStatusPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
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
