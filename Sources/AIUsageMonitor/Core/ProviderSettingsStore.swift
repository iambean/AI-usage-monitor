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

enum ProviderSettingsStore {
  private static let enabledKey = "enabled-provider-ids"
  private static let qoderKey = "qoder-configuration"
  private static let minimaxRegionKey = "minimax-region"
  private static let cursorAccountModeKey = "cursor-account-mode"

  static func enabledProviderIDs() -> [ProviderID] {
    guard let rawValues = UserDefaults.standard.array(forKey: enabledKey) as? [String] else {
      return [.codex]
    }

    let enabled = rawValues.compactMap(ProviderID.init(rawValue:))
    return ProviderCatalog.all.compactMap { metadata in
      enabled.contains(metadata.id) ? metadata.id : nil
    }
  }

  static func setEnabledProviderIDs(_ ids: [ProviderID]) {
    UserDefaults.standard.set(ids.map(\.rawValue), forKey: enabledKey)
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
