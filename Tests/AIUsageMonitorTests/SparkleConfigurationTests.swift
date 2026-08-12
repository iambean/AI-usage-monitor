import Foundation
import XCTest

final class SparkleConfigurationTests: XCTestCase {
  func testInfoPlistContainsSecureSparkleUpdateConfiguration() throws {
    let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let projectRoot = testsDirectory
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let infoPlistURL = projectRoot.appendingPathComponent("Resources/Info.plist")
    let data = try Data(contentsOf: infoPlistURL)
    let plist = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    )

    XCTAssertEqual(
      plist["SUFeedURL"] as? String,
      "https://raw.githubusercontent.com/iambean/AI-usage-monitor/main/appcast.xml"
    )
    XCTAssertFalse((plist["SUPublicEDKey"] as? String ?? "").isEmpty)
    XCTAssertEqual(plist["SUEnableAutomaticChecks"] as? Bool, false)
  }
}
