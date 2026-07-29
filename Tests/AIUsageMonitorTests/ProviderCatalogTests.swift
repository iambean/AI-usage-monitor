import XCTest

@testable import AIUsageMonitor

final class ProviderCatalogTests: XCTestCase {
  func testSupportTiersMatchIntegrationSource() {
    XCTAssertEqual(
      ProviderCatalog.metadata(for: .codex).supportTier,
      .compatible
    )
    XCTAssertEqual(
      ProviderCatalog.metadata(for: .kimi).supportTier,
      .compatible
    )
    XCTAssertEqual(
      ProviderCatalog.metadata(for: .cursor).supportTier,
      .stable
    )
    XCTAssertEqual(
      ProviderCatalog.metadata(for: .minimax).supportTier,
      .stable
    )
    XCTAssertEqual(
      ProviderCatalog.metadata(for: .deepseek).supportTier,
      .stable
    )
    XCTAssertEqual(
      ProviderCatalog.metadata(for: .glm).supportTier,
      .unavailable
    )
  }

  func testUnavailableProvidersCannotBeClassifiedAsStable() {
    for metadata in ProviderCatalog.all {
      if case .unavailable = metadata.availability {
        XCTAssertEqual(metadata.supportTier, .unavailable)
      }
    }
  }

  func testCursorDefaultsToTeamsAsTheFirstAccountMode() {
    XCTAssertEqual(CursorAccountMode.allCases.first, .teams)
  }
}
