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
  case missingInput
  case rpc(String)

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
    case .missingInput:
      return L10n.text(
        "error.codexServerWrite",
        "无法写入 Codex App Server"
      )
    case .rpc(let message):
      return message
    }
  }
}
