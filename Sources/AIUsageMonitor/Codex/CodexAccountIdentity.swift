import CryptoKit
import Foundation

struct CodexAccountIdentity: Equatable {
  let scope: String
  let label: String

  static func parse(_ response: JSONValue) -> CodexAccountIdentity? {
    guard let account = response["account"]?.objectValue else { return nil }
    let email = account["email"]?.stringValue ?? ""
    let plan = account["planType"]?.stringValue ?? ""
    let identifier = account["id"]?.stringValue ?? account["accountId"]?.stringValue ?? email
    guard !identifier.isEmpty else { return nil }
    let scope = SHA256.hash(data: Data((identifier + "|" + plan).utf8))
      .map { String(format: "%02x", $0) }.joined()
    let parts = email.split(separator: "@", maxSplits: 1)
    let masked =
      email.isEmpty
      ? "Codex"
      : String(parts.first?.prefix(2) ?? "") + "•••"
        + (parts.count == 2 ? "@" + String(parts[1]) : "")
    return CodexAccountIdentity(
      scope: scope,
      label: [masked, plan.capitalized].filter { !$0.isEmpty }.joined(separator: " · "))
  }
}
