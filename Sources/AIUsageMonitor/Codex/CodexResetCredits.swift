import Foundation

struct CodexResetCredit: Codable, Sendable, Equatable {
  let expiresAt: Date?
}

struct CodexResetCredits: Codable, Sendable, Equatable {
  // The service may return fewer detail rows than the available count.
  let availableCount: Int
  let credits: [CodexResetCredit]?
  let updatedAt: Date

  var sortedCredits: [CodexResetCredit] {
    (credits ?? []).sorted {
      ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture)
    }
  }

  var earliestKnownExpiry: Date? {
    credits?.compactMap(\.expiresAt).min()
  }

  var hasCompleteExpiryDetails: Bool {
    guard let credits else { return false }
    return credits.count == availableCount && credits.allSatisfy { $0.expiresAt != nil }
  }
}
