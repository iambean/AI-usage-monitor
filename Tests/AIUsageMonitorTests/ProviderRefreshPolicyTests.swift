import XCTest

@testable import AIUsageMonitor

final class ProviderRefreshPolicyTests: XCTestCase {
  func testPrimaryUsesProviderInterval() {
    XCTAssertEqual(
      ProviderRefreshPolicy.interval(baseInterval: 300, role: .primary),
      300
    )
  }

  func testSecondaryUsesAtLeastOneHour() {
    XCTAssertEqual(
      ProviderRefreshPolicy.interval(baseInterval: 120, role: .secondary),
      3_600
    )
    XCTAssertEqual(
      ProviderRefreshPolicy.interval(baseInterval: 7_200, role: .secondary),
      7_200
    )
  }

  func testLowPowerDoublesPrimaryAndSuspendsSecondary() {
    XCTAssertEqual(
      ProviderRefreshPolicy.interval(baseInterval: 300, role: .lowPowerPrimary),
      600
    )
    XCTAssertNil(
      ProviderRefreshPolicy.interval(baseInterval: 300, role: .suspended)
    )
  }

  func testFailureNeverPollsFasterThanSuccessfulSchedule() {
    XCTAssertEqual(
      ProviderRefreshPolicy.failureDelay(
        baseInterval: 600,
        role: .primary,
        consecutiveFailures: 1
      ),
      600
    )
    XCTAssertEqual(
      ProviderRefreshPolicy.failureDelay(
        baseInterval: 120,
        role: .secondary,
        consecutiveFailures: 6
      ),
      3_600
    )
  }
}
