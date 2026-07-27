import Foundation

struct QoderConfiguration: Codable, Sendable, Equatable {
  var organizationID = ""
  var memberID = ""
}

enum ProviderSettingsStore {
  private static let enabledKey = "enabled-provider-ids"
  private static let qoderKey = "qoder-configuration"

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
}
