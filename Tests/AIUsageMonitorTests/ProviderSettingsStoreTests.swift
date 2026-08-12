import Foundation
import XCTest

@testable import AIUsageMonitor

final class ProviderSettingsStoreTests: XCTestCase {
  func testDefaultsToCodexAsTheOnlyEnabledAndPrimaryProvider() throws {
    try withDefaults { defaults in
      let enabled = ProviderSettingsStore.enabledProviderIDs(defaults: defaults)

      XCTAssertEqual(enabled, [.codex])
      XCTAssertEqual(
        ProviderSettingsStore.primaryProviderID(
          enabledProviderIDs: enabled,
          defaults: defaults
        ),
        .codex
      )
    }
  }

  func testPersistsExactlyOneEnabledPrimaryProvider() throws {
    try withDefaults { defaults in
      ProviderSettingsStore.setEnabledProviderIDs(
        [.codex, .kimi, .deepseek],
        defaults: defaults
      )
      ProviderSettingsStore.setPrimaryProviderID(.kimi, defaults: defaults)

      let enabled = ProviderSettingsStore.enabledProviderIDs(defaults: defaults)
      XCTAssertEqual(
        ProviderSettingsStore.primaryProviderID(
          enabledProviderIDs: enabled,
          defaults: defaults
        ),
        .kimi
      )
    }
  }

  func testInvalidStoredPrimaryFallsBackToCodexOrFirstEnabledProvider() throws {
    try withDefaults { defaults in
      ProviderSettingsStore.setPrimaryProviderID(.deepseek, defaults: defaults)

      XCTAssertEqual(
        ProviderSettingsStore.primaryProviderID(
          enabledProviderIDs: [.codex, .kimi],
          defaults: defaults
        ),
        .codex
      )
      XCTAssertEqual(
        ProviderSettingsStore.primaryProviderID(
          enabledProviderIDs: [.kimi],
          defaults: defaults
        ),
        .kimi
      )
    }
  }

  func testEmptyPersistedEnabledListRecoversToCodex() throws {
    try withDefaults { defaults in
      ProviderSettingsStore.setEnabledProviderIDs([], defaults: defaults)
      XCTAssertEqual(
        ProviderSettingsStore.enabledProviderIDs(defaults: defaults),
        [.codex]
      )
    }
  }

  private func withDefaults(
    _ body: (UserDefaults) throws -> Void
  ) throws {
    let suiteName = "ProviderSettingsStoreTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body(defaults)
  }
}
