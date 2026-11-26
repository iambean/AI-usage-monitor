import Foundation

struct CodexCreditBalance: Codable, Equatable, Sendable {
  enum Amount: Codable, Equatable, Sendable {
    case balance(Decimal)
    case unlimited
    case available
    case noneAvailable
  }

  let amount: Amount
  let expiresAt: Date?

  init?(snapshot: JSONValue?) {
    guard let credits = snapshot?.objectValue else { return nil }
    if credits["unlimited"] == .bool(true) {
      amount = .unlimited
    } else if let raw = credits["balance"], raw != .null {
      guard let text = raw.stringValue,
        let value = try? JSONDecoder().decode(Decimal.self, from: Data(text.utf8))
      else { return nil }
      amount = .balance(value)
    } else {
      guard case .bool(let hasCredits) = credits["hasCredits"] else { return nil }
      amount = hasCredits ? .available : .noneAvailable
    }

    // Use only an expiry supplied for this balance. Window resets and reset grants
    // have independent lifetimes.
    expiresAt = credits["expiresAt"]?.doubleValue.flatMap { timestamp in
      guard timestamp.isFinite, timestamp > 0 else { return nil }
      return Date(timeIntervalSince1970: timestamp)
    }
  }
}
