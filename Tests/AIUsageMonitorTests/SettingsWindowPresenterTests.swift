import AppKit
import XCTest

@testable import AIUsageMonitor

@MainActor
final class SettingsWindowPresenterTests: XCTestCase {
  func testNaturalWindowPolicyRestoresNormalLayerAndSpaceBehavior() {
    let window = NSPanel()
    window.level = .statusBar
    window.collectionBehavior.insert(.canJoinAllSpaces)
    window.collectionBehavior.insert(.fullScreenAuxiliary)

    WindowPresentationPolicy.natural.apply(to: window)

    XCTAssertEqual(window.level, .normal)
    XCTAssertFalse(window.hidesOnDeactivate)
    XCTAssertFalse(window.collectionBehavior.contains(.canJoinAllSpaces))
    XCTAssertFalse(window.collectionBehavior.contains(.fullScreenAuxiliary))
  }

  func testOpensBeforeSchedulingWindowFocus() {
    var events: [String] = []
    var scheduledFocus: (() -> Void)?
    let presenter = SettingsWindowPresenter(
      open: {
        events.append("open")
      },
      schedule: { action in
        events.append("schedule")
        scheduledFocus = action
      },
      focus: {
        events.append("focus")
      }
    )

    presenter.present()

    XCTAssertEqual(events, ["open", "schedule"])
    scheduledFocus?()
    XCTAssertEqual(events, ["open", "schedule", "focus"])
  }
}
