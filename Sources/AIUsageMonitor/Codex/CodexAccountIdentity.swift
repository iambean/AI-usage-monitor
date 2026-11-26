import CryptoKit
import Foundation

struct CodexPlanObservation: Codable, Equatable, Sendable {
  let accountKey: String
  let tier: String
}

struct CodexAccountIdentity: Equatable {
  let accountKey: String
  let planObservation: CodexPlanObservation?
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
    let displayName =
      ProviderAccountLabel.firstNonempty(
        email, account["username"]?.stringValue,
        account["name"]?.stringValue) ?? "Codex"
    let accountKey = SHA256.hash(data: Data(identifier.utf8))
      .map { String(format: "%02x", $0) }.joined()
    return CodexAccountIdentity(
      accountKey: accountKey,
      planObservation: plan.isEmpty || plan == "unknown"
        ? nil : CodexPlanObservation(accountKey: accountKey, tier: plan),
      scope: scope,
      label: [displayName, plan.capitalized].filter { !$0.isEmpty }.joined(separator: " · "))
  }
}
