import Foundation

struct CodexCreditGrant: Codable, Equatable, Sendable {
  let amount: Int
  let expiresOn: String

  var isValid: Bool {
    amount > 0 && Self.parsedDate(from: expiresOn) != nil
  }

  func isExpired(on date: Date, calendar: Calendar = .current) -> Bool {
    guard isValid else { return true }
    var style = Self.isoDateStyle
    style.timeZone = calendar.timeZone
    return date.formatted(style) > expiresOn
  }

  func displayExpiry(locale: Locale = L10n.locale) -> String? {
    var style = Self.isoDateStyle
    style.timeZone = .current
    guard let date = try? style.parse(expiresOn) else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = style.timeZone
    let displayStyle = Date.FormatStyle(
      date: .abbreviated,
      time: .omitted,
      locale: locale,
      calendar: calendar,
      timeZone: style.timeZone
    )
    return date.formatted(displayStyle)
  }

  private static var isoDateStyle: Date.ISO8601FormatStyle {
    Date.ISO8601FormatStyle()
      .year()
      .month()
      .day()
      .dateSeparator(.dash)
  }

  private static func parsedDate(from value: String) -> Date? {
    guard value.utf8.count == 10, !value.hasPrefix("0000") else { return nil }
    let style = isoDateStyle
    guard let date = try? style.parse(value), date.formatted(style) == value else {
      return nil
    }
    return date
  }
}

enum CodexCreditGrantStore {
  private static let fileName = "codex-credit-grants.json"

  static func grant(
    for accountKey: String?,
    now: Date = Date(),
    fileURL: URL? = nil
  ) -> CodexCreditGrant? {
    guard let accountKey, !accountKey.isEmpty,
      let url = fileURL ?? defaultURL(),
      let data = try? Data(contentsOf: url),
      let grant = readGrant(for: accountKey, from: data),
      grant.isValid,
      !grant.isExpired(on: now)
    else {
      return nil
    }
    return grant
  }

  private static func readGrant(for accountKey: String, from data: Data) -> CodexCreditGrant? {
    guard
      let root = try? JSONSerialization.jsonObject(with: data),
      let grants = root as? [String: Any],
      let rawGrant = grants[accountKey],
      let grantData = try? JSONSerialization.data(withJSONObject: rawGrant, options: [.fragmentsAllowed]),
      let grant = try? JSONDecoder().decode(CodexCreditGrant.self, from: grantData)
    else {
      return nil
    }
    return grant
  }

  private static func defaultURL(
    fileManager: FileManager = .default
  ) -> URL? {
    guard
      let applicationSupport = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      return nil
    }
    return applicationSupport
      .appendingPathComponent("AI Usage Monitor", isDirectory: true)
      .appendingPathComponent(fileName, isDirectory: false)
  }
}
