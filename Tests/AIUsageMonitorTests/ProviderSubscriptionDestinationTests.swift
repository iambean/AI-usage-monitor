import Foundation
import XCTest

@testable import AIUsageMonitor

final class ProviderSubscriptionDestinationTests: XCTestCase {
  func testProviderSubscriptionPages() {
    let expectedURLs: [ProviderID: String] = [
      .codex: "https://chatgpt.com/pricing",
      .claude: "https://claude.ai/upgrade",
      .cursor: "https://cursor.com/pricing",
      .kimi: "https://www.kimi.com/membership/pricing",
      .deepseek: "https://platform.deepseek.com/top_up",
      .qoder: "https://qoder.com/pricing",
      .ark: "https://www.volcengine.com/activity/codingplan",
      .aliyun: "https://common-buy.aliyun.com/coding-plan",
      .tencent: "https://cloud.tencent.com/act/pro/codingplan",
      .glm: "https://bigmodel.cn/coding-plan",
    ]

    for (providerID, expectedURL) in expectedURLs {
      XCTAssertEqual(
        ProviderSubscriptionDestination.url(for: providerID).absoluteString,
        expectedURL
      )
    }
  }

  func testMiniMaxSubscriptionPageFollowsConfiguredRegion() {
    XCTAssertEqual(
      ProviderSubscriptionDestination.url(
        for: .minimax,
        miniMaxRegion: .global
      ).absoluteString,
      "https://platform.minimax.io/subscribe/token-plan"
    )
    XCTAssertEqual(
      ProviderSubscriptionDestination.url(
        for: .minimax,
        miniMaxRegion: .china
      ).absoluteString,
      "https://platform.minimaxi.com/subscribe/token-plan"
    )
  }

  func testAutomaticMiniMaxSubscriptionPageFollowsLocaleRegion() {
    XCTAssertEqual(
      ProviderSubscriptionDestination.url(
        for: .minimax,
        miniMaxRegion: .automatic,
        locale: Locale(identifier: "zh_CN")
      ).absoluteString,
      "https://platform.minimaxi.com/subscribe/token-plan"
    )
    XCTAssertEqual(
      ProviderSubscriptionDestination.url(
        for: .minimax,
        miniMaxRegion: .automatic,
        locale: Locale(identifier: "en_US")
      ).absoluteString,
      "https://platform.minimax.io/subscribe/token-plan"
    )
  }
}
