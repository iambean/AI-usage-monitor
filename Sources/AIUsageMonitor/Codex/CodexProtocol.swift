import Foundation

struct CodexRPCRequest: Encodable {
  let method: String
  let id: Int
  let params: JSONValue
}

struct CodexRPCNotification: Encodable {
  let method: String
  let params: JSONValue
}

struct CodexRPCEnvelope: Decodable {
  let id: Int?
  let method: String?
  let result: JSONValue?
  let params: JSONValue?
  let error: CodexRPCError?
}

struct CodexRPCError: Decodable {
  let code: Int?
  let message: String
}

struct CodexNotification: Sendable {
  let method: String
  let params: JSONValue
}

enum CodexClientError: LocalizedError {
  case executableNotFound(String)
  case processExited(Int32)
  case timeout
  case missingInput
  case rpc(String)

  var isAuthenticationFailure: Bool {
    guard case .rpc(let message) = self else { return false }
    let text = message.lowercased()
    return text.range(of: #"\b401\b"#, options: .regularExpression) != nil
      || text.contains("unauthorized")
      || text.contains("token_expired")
      || text.contains("token_invalidated")
      || text.contains("refresh_token_expired")
      || text.contains("refresh_token_reused")
      || text.contains("refresh_token_invalidated")
      || (text.contains("refresh token") && text.contains("log in again"))
  }

  var recoverySuggestion: String? {
    guard isAuthenticationFailure else { return nil }
    return L10n.text(
      "recovery.codexAuthentication",
      "自动恢复登录未成功。请在终端运行 codex login，完成登录后点击刷新。"
    )
  }

  var errorDescription: String? {
    switch self {
    case .executableNotFound(let path):
      return L10n.format("error.codexNotFound", "找不到 Codex CLI：%@", path)
    case .processExited(let code):
      return L10n.format(
        "error.codexServerExited",
        "Codex App Server 已退出（%d）",
        code
      )
    case .timeout:
      return L10n.text("monitor.requestTimeout", "查询超时，请重试")
    case .missingInput:
      return L10n.text(
        "error.codexServerWrite",
        "无法写入 Codex App Server"
      )
    case .rpc(let message):
      if isAuthenticationFailure {
        return L10n.text("error.codexAuthentication", "Codex 登录状态已失效，暂时无法读取用量。")
      }
      return message
    }
  }
}
