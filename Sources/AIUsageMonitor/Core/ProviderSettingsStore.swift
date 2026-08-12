import Foundation

struct QoderConfiguration: Codable, Sendable, Equatable {
  var organizationID = ""
  var memberID = ""
}

enum CursorAccountMode: String, Codable, CaseIterable, Sendable {
  case teams
  case personal

  var title: String {
    switch self {
    case .teams:
      return "Teams"
    case .personal:
      return L10n.text("settings.cursorPersonal", "个人")
    }
  }
}

enum MiniMaxRegion: String, Codable, CaseIterable, Sendable {
  case automatic
  case global
  case china

  var title: String {
    switch self {
    case .automatic:
      return L10n.text("settings.regionAutomatic", "自动检测")
    case .global:
      return L10n.text("settings.regionGlobal", "海外")
    case .china:
      return L10n.text("settings.regionChina", "中国大陆")
    }
  }
}

enum ProviderOrder {
  static func withPrimaryFirst(
    _ ids: [ProviderID],
    primary: ProviderID
  ) -> [ProviderID] {
    let enabled = Set(ids)
    let catalogOrder = ProviderCatalog.all.map(\.id).filter(enabled.contains)
    guard enabled.contains(primary) else { return catalogOrder }
    return [primary] + catalogOrder.filter { $0 != primary }
  }
}

enum ProviderSettingsStore {
  private static let enabledKey = "enabled-provider-ids"
  private static let primaryKey = "primary-provider-id"
  private static let qoderKey = "qoder-configuration"
  private static let minimaxRegionKey = "minimax-region"
  private static let cursorAccountModeKey = "cursor-account-mode"

  static func enabledProviderIDs(defaults: UserDefaults = .standard) -> [ProviderID] {
    guard let rawValues = defaults.array(forKey: enabledKey) as? [String] else {
      return [.codex]
    }

    let enabled = Set(rawValues.compactMap(ProviderID.init(rawValue:)))
    let normalized = ProviderCatalog.all.compactMap { metadata -> ProviderID? in
      guard case .available = metadata.availability else { return nil }
      return enabled.contains(metadata.id) ? metadata.id : nil
    }
    return normalized.isEmpty ? [.codex] : normalized
  }

  static func setEnabledProviderIDs(
    _ ids: [ProviderID],
    defaults: UserDefaults = .standard
  ) {
    defaults.set(ids.map(\.rawValue), forKey: enabledKey)
  }

  static func primaryProviderID(
    enabledProviderIDs: [ProviderID],
    defaults: UserDefaults = .standard
  ) -> ProviderID {
    let stored = defaults.string(forKey: primaryKey).flatMap(ProviderID.init(rawValue:))
    if let stored, enabledProviderIDs.contains(stored) {
      return stored
    }
    if enabledProviderIDs.contains(.codex) {
      return .codex
    }
    return enabledProviderIDs.first ?? .codex
  }

  static func setPrimaryProviderID(
    _ id: ProviderID,
    defaults: UserDefaults = .standard
  ) {
    defaults.set(id.rawValue, forKey: primaryKey)
  }

  static func qoderConfiguration() -> QoderConfiguration {
    guard
      let data = UserDefaults.standard.data(forKey: qoderKey),
      let value = try? JSONDecoder().decode(QoderConfiguration.self, from: data)
    else {
      return QoderConfiguration()
    }
    return value
  }

  static func setQoderConfiguration(_ configuration: QoderConfiguration) {
    guard let data = try? JSONEncoder().encode(configuration) else { return }
    UserDefaults.standard.set(data, forKey: qoderKey)
  }

  static func miniMaxRegion() -> MiniMaxRegion {
    guard
      let rawValue = UserDefaults.standard.string(forKey: minimaxRegionKey),
      let value = MiniMaxRegion(rawValue: rawValue)
    else {
      return .automatic
    }
    return value
  }

  static func setMiniMaxRegion(_ region: MiniMaxRegion) {
    UserDefaults.standard.set(region.rawValue, forKey: minimaxRegionKey)
  }

  static func cursorAccountMode() -> CursorAccountMode {
    guard
      let rawValue = UserDefaults.standard.string(forKey: cursorAccountModeKey),
      let value = CursorAccountMode(rawValue: rawValue)
    else {
      return .teams
    }
    return value
  }

  static func setCursorAccountMode(_ mode: CursorAccountMode) {
    UserDefaults.standard.set(mode.rawValue, forKey: cursorAccountModeKey)
  }
}
