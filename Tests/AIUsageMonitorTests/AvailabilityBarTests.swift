@testable import AIUsageMonitor
import XCTest

final class AvailabilityBarTests: XCTestCase {
  func testHueMapsAvailableFractionFromRedToGreen() {
    XCTAssertEqual(AvailabilityColorScale.hue(for: 0), 0, accuracy: 0.000_001)
    XCTAssertEqual(AvailabilityColorScale.hue(for: 0.5), 1.0 / 6.0, accuracy: 0.000_001)
    XCTAssertEqual(AvailabilityColorScale.hue(for: 1), 1.0 / 3.0, accuracy: 0.000_001)
  }

  func testHueClampsOutOfRangeFractions() {
    XCTAssertEqual(AvailabilityColorScale.hue(for: -0.5), 0, accuracy: 0.000_001)
    XCTAssertEqual(AvailabilityColorScale.hue(for: 1.5), 1.0 / 3.0, accuracy: 0.000_001)
  }
}
