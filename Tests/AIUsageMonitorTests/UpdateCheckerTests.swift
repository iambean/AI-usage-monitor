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
    let responseURL = URL(
      string: "https://raw.githubusercontent.com/iambean/AI-usage-monitor/main/appcast.xml"
    )!
    let checker = UpdateChecker(defaults: defaults) { request in
      XCTAssertEqual(request.url, responseURL)
      let data = Data(
        """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <item>
              <title>Version 0.3.0</title>
              <link>https://github.com/iambean/AI-usage-monitor/releases/tag/v0.3.0</link>
              <sparkle:shortVersionString>0.3.0</sparkle:shortVersionString>
              <enclosure url="https://github.com/iambean/AI-usage-monitor/releases/download/v0.3.0/AI-Usage-0.3.0-arm64-adhoc.zip" />
            </item>
          </channel>
        </rss>
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
    XCTAssertEqual(version, "0.3.0")
  }

  func testReportsRepositoryWithoutReleasesSeparately() async throws {
    let suiteName = "UpdateCheckerTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let responseURL = URL(string: "https://api.github.com")!
    let requestCounter = RequestCounter()
    let checker = UpdateChecker(defaults: defaults) { _ in
      await requestCounter.increment()
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
      force: false,
      now: Date(timeIntervalSince1970: 1_000_000)
    )
    let cached = try await checker.check(
      currentVersion: "0.3.0",
      force: false,
      now: Date(timeIntervalSince1970: 1_000_100)
    )

    XCTAssertEqual(result, .noRelease)
    XCTAssertEqual(cached, .noRelease)
    let requestCount = await requestCounter.value
    XCTAssertEqual(requestCount, 1)
  }
}

private actor RequestCounter {
  private(set) var value = 0

  func increment() {
    value += 1
  }
}
