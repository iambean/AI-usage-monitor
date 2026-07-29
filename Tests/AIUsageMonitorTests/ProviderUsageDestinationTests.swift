import Foundation
import XCTest

@testable import AIUsageMonitor

final class ProviderUsageDestinationTests: XCTestCase {
  func testProviderUsagePages() {
    let expectedURLs: [ProviderID: String] = [
      .codex: "https://chatgpt.com/codex/settings/usage",
      .claude: "https://claude.ai/settings/usage",
      .cursor: "https://cursor.com/dashboard/usage",
      .kimi: "https://www.kimi.com/code/console",
      .deepseek: "https://platform.deepseek.com/usage",
      .qoder: "https://qoder.com/account/settings/usage",
      .glm: "https://bigmodel.cn/coding-plan/personal/usage",
    ]

    for (providerID, expectedURL) in expectedURLs {
      XCTAssertEqual(
        ProviderUsageDestination.url(for: providerID).absoluteString,
        expectedURL
      )
    }
  }

  func testMiniMaxUsagePageFollowsConfiguredRegion() {
    XCTAssertEqual(
      ProviderUsageDestination.url(
        for: .minimax,
        miniMaxRegion: .global
      ).absoluteString,
      "https://platform.minimax.io/console/usage"
    )
    XCTAssertEqual(
      ProviderUsageDestination.url(
        for: .minimax,
        miniMaxRegion: .china
      ).absoluteString,
      "https://platform.minimaxi.com/console/usage"
    )
  }

  func testAutomaticMiniMaxUsagePageFollowsLocaleRegion() {
    XCTAssertEqual(
      ProviderUsageDestination.url(
        for: .minimax,
        miniMaxRegion: .automatic,
        locale: Locale(identifier: "zh_CN")
      ).absoluteString,
      "https://platform.minimaxi.com/console/usage"
    )
    XCTAssertEqual(
      ProviderUsageDestination.url(
        for: .minimax,
        miniMaxRegion: .automatic,
        locale: Locale(identifier: "en_US")
      ).absoluteString,
      "https://platform.minimax.io/console/usage"
    )
  }
}
