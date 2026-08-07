import Foundation

enum ProviderUsageDestination {
  static func url(
    for providerID: ProviderID,
    miniMaxRegion: MiniMaxRegion? = nil,
    locale: Locale = .current
  ) -> URL {
    switch providerID {
    case .codex:
      return URL(string: "https://chatgpt.com/codex/settings/usage")!
    case .claude:
      return URL(string: "https://claude.ai/settings/usage")!
    case .cursor:
      return URL(string: "https://cursor.com/dashboard/usage")!
    case .kimi:
      return URL(string: "https://www.kimi.com/code/console")!
    case .minimax:
      return miniMaxUsageURL(
        region: miniMaxRegion ?? ProviderSettingsStore.miniMaxRegion(),
        locale: locale
      )
    case .deepseek:
      return URL(string: "https://platform.deepseek.com/usage")!
    case .qoder:
      return URL(string: "https://qoder.com/account/settings/usage")!
    case .ark:
      return URL(string: "https://www.volcengine.com/activity/codingplan")!
    case .aliyun:
      return URL(string: "https://bailian.console.aliyun.com/cn-beijing/?tab=plan")!
    case .tencent:
      return URL(string: "https://cloud.tencent.com/act/pro/codingplan")!
    case .glm:
      return URL(string: "https://bigmodel.cn/coding-plan/personal/usage")!
    }
  }

  private static func miniMaxUsageURL(region: MiniMaxRegion, locale: Locale) -> URL {
    let usesChinaConsole =
      region == .china
      || (region == .automatic && locale.region?.identifier == "CN")
    let host = usesChinaConsole ? "platform.minimaxi.com" : "platform.minimax.io"
    return URL(string: "https://\(host)/console/usage")!
  }
}
