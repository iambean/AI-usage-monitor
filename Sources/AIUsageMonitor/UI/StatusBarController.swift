import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
  private let model: AppModel
  private let statusItem: NSStatusItem
  private let panel: PersistentStatusPanel
  private let hostingController: NSHostingController<AnyView>
  private var cancellables: Set<AnyCancellable> = []

  init(model: AppModel) {
    self.model = model
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    let content = AnyView(
      MenuBarContentView()
        .environmentObject(model)
    )
    hostingController = NSHostingController(rootView: content)
    panel = PersistentStatusPanel(
      contentRect: NSRect(x: 0, y: 0, width: 350, height: 1),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    super.init()

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
    model.$providerStates
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
    button.title = " \(MenuBarSummary.displayText(for: model.providerStates))"
  }

  private func showPanel() {
    model.panelDidOpen()
    resizeAndPositionPanel()
    WindowPresentationPolicy.natural.apply(to: panel)
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }

  private func resizeAndPositionPanel() {
    hostingController.view.layoutSubtreeIfNeeded()
    let fittingSize = hostingController.view.fittingSize
    let panelSize = NSSize(
      width: 350,
      height: max(fittingSize.height, 1)
    )
    panel.setContentSize(panelSize)

    guard
      let button = statusItem.button,
      let statusWindow = button.window,
      let screen = statusWindow.screen ?? NSScreen.main
    else {
      return
    }

    let buttonRect = button.convert(button.bounds, to: nil)
    let buttonFrame = statusWindow.convertToScreen(buttonRect)
    let visibleFrame = screen.visibleFrame
    let horizontalPadding: CGFloat = 8
    let verticalGap: CGFloat = 6
    let preferredX = buttonFrame.maxX - panelSize.width
    let x = min(
      max(preferredX, visibleFrame.minX + horizontalPadding),
      visibleFrame.maxX - panelSize.width - horizontalPadding
    )
    let y = buttonFrame.minY - panelSize.height - verticalGap
    panel.setFrameOrigin(NSPoint(x: x, y: y))
  }
}

private final class PersistentStatusPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
