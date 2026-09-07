import Foundation
import SwiftUI

struct UsageAlertRule: Codable, Equatable {
  var enabled = false
  var thresholds: [Double] = [20, 10, 5]
  var balanceThreshold: Double = 10
  var notifyRecovery = false
}

struct MonitorPreferences: Codable, Equatable {
  var compact = false
  var appearance = "system"
  var selectedMetrics: [String: String] = [:]
  var providerOrder: [ProviderID] = []
  var collapsedProviders: [ProviderID] = []
  var refreshAfterWake = true
  var reduceInLowPower = true
  var retentionDays = 30
  var showForecast = true
  var notificationsEnabled = false
  var alertRules: [String: UsageAlertRule] = [:]
  var expiryReminderDays: [Int] = [3, 1]
  var quietHoursEnabled = false
  var quietStartHour = 22
  var quietEndHour = 8
  var snoozedUntil: Date?

  static let storageKey = "monitor-preferences-v1"

  static func load(defaults: UserDefaults = .standard) -> MonitorPreferences {
    guard let data = defaults.data(forKey: storageKey),
      var value = try? JSONDecoder().decode(Self.self, from: data)
    else { return Self() }
    if ![7, 30, 90].contains(value.retentionDays) { value.retentionDays = 30 }
    value.quietStartHour = max(0, min(23, value.quietStartHour))
    value.quietEndHour = max(0, min(23, value.quietEndHour))
    return value
  }

  func save(defaults: UserDefaults = .standard) {
    guard let data = try? JSONEncoder().encode(self) else { return }
    defaults.set(data, forKey: Self.storageKey)
  }

  static func metricKey(providerID: ProviderID, metricID: String) -> String {
    "\(providerID.rawValue)|\(metricID)"
  }

  func isQuiet(at now: Date, calendar: Calendar = .current) -> Bool {
    if let snoozedUntil, now < snoozedUntil { return true }
    guard quietHoursEnabled else { return false }
    let hour = calendar.component(.hour, from: now)
    if quietStartHour == quietEndHour { return true }
    return quietStartHour < quietEndHour
      ? hour >= quietStartHour && hour < quietEndHour
      : hour >= quietStartHour || hour < quietEndHour
  }

  func ordered(_ ids: [ProviderID]) -> [ProviderID] {
    var seen = Set<ProviderID>()
    return (providerOrder + ids).filter { ids.contains($0) && seen.insert($0).inserted }
  }
}
