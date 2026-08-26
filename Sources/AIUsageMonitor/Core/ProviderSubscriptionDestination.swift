import Foundation

enum ProviderSubscriptionDestination {
  static func url(
    for providerID: ProviderID,
    miniMaxRegion: MiniMaxRegion? = nil,
    locale: Locale = .current
  ) -> URL {
    switch providerID {
    case .codex:
      return URL(string: "https://chatgpt.com/pricing")!
    case .claude:
      return URL(string: "https://claude.ai/upgrade")!
    case .cursor:
      return URL(string: "https://cursor.com/pricing")!
    case .kimi:
      return URL(string: "https://www.kimi.com/membership/pricing")!
    case .minimax:
      return miniMaxSubscriptionURL(
        region: miniMaxRegion ?? ProviderSettingsStore.miniMaxRegion(),
        locale: locale
      )
    case .deepseek:
      return URL(string: "https://platform.deepseek.com/top_up")!
    case .qoder:
      return URL(string: "https://qoder.com/pricing")!
    case .ark:
      return URL(string: "https://www.volcengine.com/activity/codingplan")!
    case .aliyun:
      return URL(string: "https://common-buy.aliyun.com/coding-plan")!
    case .tencent:
      return URL(string: "https://cloud.tencent.com/act/pro/codingplan")!
    case .glm:
      return URL(string: "https://bigmodel.cn/coding-plan")!
    }
  }

  private static func miniMaxSubscriptionURL(
    region: MiniMaxRegion,
    locale: Locale
  ) -> URL {
    let usesChinaConsole =
      region == .china
      || (region == .automatic && locale.region?.identifier == "CN")
    let host = usesChinaConsole ? "platform.minimaxi.com" : "platform.minimax.io"
    return URL(string: "https://\(host)/subscribe/token-plan")!
  }
}
