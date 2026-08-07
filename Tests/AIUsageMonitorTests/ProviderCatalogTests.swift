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
    XCTAssertEqual(
      ProviderCatalog.metadata(for: .ark).supportTier,
      .unavailable
    )
    XCTAssertEqual(
      ProviderCatalog.metadata(for: .aliyun).supportTier,
      .unavailable
    )
    XCTAssertEqual(
      ProviderCatalog.metadata(for: .tencent).supportTier,
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

  func testRequestedCodingPlansAreVisibleButUnavailable() {
    let providerIDs: [ProviderID] = [.ark, .aliyun, .tencent]

    for providerID in providerIDs {
      let metadata = ProviderCatalog.metadata(for: providerID)
      guard case .unavailable(let reason) = metadata.availability else {
        return XCTFail("Expected \(providerID.rawValue) to be unavailable")
      }
      XCTAssertFalse(reason.isEmpty)
    }
  }
}
