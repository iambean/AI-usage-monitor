import Foundation
import Security

enum ProviderSecret: String {
  case minimaxAPIKey = "minimax-api-key"
  case deepseekAPIKey = "deepseek-api-key"
  case qoderAPIKey = "qoder-api-key"
  case cursorAdminAPIKey = "cursor-admin-api-key"
}

enum KeychainStore {
  private static let service = "com.ai-usage-monitor.credentials"

  static func read(_ secret: ProviderSecret) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: secret.rawValue,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  static func write(_ value: String, for secret: ProviderSecret) throws {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      delete(secret)
      return
    }

    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: secret.rawValue,
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: Data(trimmed.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]

    let updateStatus = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecItemNotFound {
      var insert = base
      for (key, value) in attributes {
        insert[key] = value
      }
      let status = SecItemAdd(insert as CFDictionary, nil)
      guard status == errSecSuccess else { throw KeychainError(status: status) }
    } else if updateStatus != errSecSuccess {
      throw KeychainError(status: updateStatus)
    }
  }

  static func delete(_ secret: ProviderSecret) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: secret.rawValue,
    ]
    SecItemDelete(query as CFDictionary)
  }
}

actor KeychainAccessCoordinator {
  static let shared = KeychainAccessCoordinator()

  private var loadedSecrets: Set<ProviderSecret> = []
  private var cachedValues: [ProviderSecret: String] = [:]

  func read(_ secret: ProviderSecret) -> String? {
    if loadedSecrets.contains(secret) {
      return cachedValues[secret]
    }
    let value = KeychainStore.read(secret)
    loadedSecrets.insert(secret)
    cachedValues[secret] = value
    return value
  }

  func write(_ value: String, for secret: ProviderSecret) throws {
    try KeychainStore.write(value, for: secret)
    loadedSecrets.insert(secret)
    cachedValues[secret] = value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct KeychainError: LocalizedError {
  let status: OSStatus

  var errorDescription: String? {
    SecCopyErrorMessageString(status, nil) as String?
      ?? L10n.format("error.keychainWrite", "无法保存凭证（%d）", status)
  }
}
