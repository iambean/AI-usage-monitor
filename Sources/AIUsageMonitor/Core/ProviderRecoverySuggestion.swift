import Foundation

enum ProviderRecoverySuggestion {
  static func text(for providerID: ProviderID) -> String {
    switch providerID {
    case .codex:
      return L10n.text(
        "recovery.codex",
        "请确认 Codex CLI 已登录并可正常运行，然后点击刷新。"
      )
    case .claude:
      return L10n.text(
        "recovery.claude",
        "请先运行一次 Claude Code，再返回应用点击刷新。"
      )
    case .kimi:
      return L10n.text(
        "recovery.kimi",
        "请在 Kimi Code 中运行 /usage；若 CLI 正常，再返回应用点击刷新。"
      )
    case .cursor, .minimax, .deepseek, .qoder:
      return L10n.text(
        "recovery.apiProvider",
        "请检查凭证和订阅状态，然后重新配置或点击刷新。"
      )
    case .glm:
      return L10n.text(
        "recovery.unavailable",
        "该数据源尚未开放，请等待后续版本支持。"
      )
    }
  }

  static func text(for error: Error, providerID: ProviderID) -> String {
    (error as? any LocalizedError)?.recoverySuggestion ?? text(for: providerID)
  }
}
