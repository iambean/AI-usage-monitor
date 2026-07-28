import Foundation
import XCTest

@testable import AIUsageMonitor

final class UpdateCheckerTests: XCTestCase {
  func testVersionComparisonHandlesPrefixAndMissingComponents() {
    XCTAssertLessThan(AppVersion("v0.2.10"), AppVersion("0.3.0"))
    XCTAssertEqual(AppVersion("1.0"), AppVersion("1.0.0"))
    XCTAssertFalse(AppVersion("2.0.0") < AppVersion("1.9.9"))
  }

  func testFindsNewReleaseAndCachesDailyResult() async throws {
    let suiteName = "UpdateCheckerTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let responseURL = URL(string: "https://api.github.com")!
    let checker = UpdateChecker(defaults: defaults) { _ in
      let data = Data(
        """
        {"tag_name":"v0.3.0","html_url":"https://github.com/iambean/codex-usage-monitor/releases/tag/v0.3.0"}
        """.utf8
      )
      let response = HTTPURLResponse(
        url: responseURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (data, response)
    }

    let first = try await checker.check(
      currentVersion: "0.2.10",
      force: false,
      now: Date(timeIntervalSince1970: 1_000_000)
    )
    let cached = try await checker.check(
      currentVersion: "0.2.10",
      force: false,
      now: Date(timeIntervalSince1970: 1_000_100)
    )

    XCTAssertEqual(first, cached)
    guard case .available(let version, _) = first else {
      return XCTFail("Expected an available update")
    }
    XCTAssertEqual(version, "v0.3.0")
  }

  func testTreatsRepositoryWithoutReleasesAsUpToDate() async throws {
    let suiteName = "UpdateCheckerTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let responseURL = URL(string: "https://api.github.com")!
    let checker = UpdateChecker(defaults: defaults) { _ in
      let response = HTTPURLResponse(
        url: responseURL,
        statusCode: 404,
        httpVersion: nil,
        headerFields: nil
      )!
      return (Data(), response)
    }

    let result = try await checker.check(
      currentVersion: "0.3.0",
      force: false
    )

    XCTAssertEqual(result, .upToDate)
  }
}
