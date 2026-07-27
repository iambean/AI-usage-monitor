import XCTest

@testable import AIUsageMonitor

@MainActor
final class SettingsWindowPresenterTests: XCTestCase {
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
