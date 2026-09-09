import XCTest

@testable import AIUsageMonitor

final class LegacyDisclosurePreferencesTests: XCTestCase {
  func testOldCollapsedProvidersAreIgnoredWithoutResettingOtherPreferences() throws {
    var preferences = MonitorPreferences()
    preferences.compact = true
    preferences.providerOrder = [.kimi, .codex]
    preferences.selectedMetrics = ["codex": "codex.secondary"]
    preferences.retentionDays = 90
    let data = try JSONEncoder().encode(preferences)
    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    legacy["collapsedProviders"] = ["codex", "kimi", "minimax"]
    let suite = "LegacyDisclosurePreferencesTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(
      try JSONSerialization.data(withJSONObject: legacy), forKey: MonitorPreferences.storageKey)
    let loaded = MonitorPreferences.load(defaults: defaults)
    XCTAssertEqual(loaded, preferences)
    loaded.save(defaults: defaults)
    let saved = try XCTUnwrap(defaults.data(forKey: MonitorPreferences.storageKey))
    let savedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
    XCTAssertNil(savedObject["collapsedProviders"])
  }
}
