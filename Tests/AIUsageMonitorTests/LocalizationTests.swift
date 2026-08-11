import Foundation
import XCTest

@testable import AIUsageMonitor

final class LocalizationTests: XCTestCase {
  func testChineseAndEnglishContainTheSameKeys() throws {
    let chinese = try strings(language: "zh-Hans")
    let english = try strings(language: "en")

    XCTAssertEqual(Set(chinese.keys), Set(english.keys))
    XCTAssertEqual(chinese["main.title"], "AI 用量")
    XCTAssertEqual(english["main.title"], "AI Usage")
  }

  func testChineseIsTheApplicationFallbackLanguage() throws {
    let infoData = try Data(
      contentsOf: repositoryRoot.appendingPathComponent("Resources/Info.plist"))
    let info = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: infoData, format: nil)
        as? [String: Any]
    )

    XCTAssertEqual(info["CFBundleDevelopmentRegion"] as? String, "zh-Hans")
    XCTAssertEqual(info["CFBundleLocalizations"] as? [String], ["zh-Hans", "en"])
  }

  func testAppLanguageDefaultsToSystemAndPersistsSelection() throws {
    let suiteName = "LocalizationTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    XCTAssertEqual(AppLanguageStore.load(defaults: defaults), .system)
    AppLanguageStore.save(.english, defaults: defaults)
    XCTAssertEqual(AppLanguageStore.load(defaults: defaults), .english)
    AppLanguageStore.save(.simplifiedChinese, defaults: defaults)
    XCTAssertEqual(AppLanguageStore.load(defaults: defaults), .simplifiedChinese)
  }

  func testEveryLanguageHasTheExpectedLocale() {
    XCTAssertEqual(AppLanguage.system.locale, .current)
    XCTAssertEqual(AppLanguage.simplifiedChinese.locale.identifier, "zh-Hans")
    XCTAssertEqual(AppLanguage.english.locale.identifier, "en")
  }

  func testEveryLocalizedSourceKeyExistsInBothLanguages() throws {
    let localizedKeys = Set(try strings(language: "zh-Hans").keys)
    let sourceDirectory = repositoryRoot.appendingPathComponent("Sources/AIUsageMonitor")
    let enumerator = try XCTUnwrap(
      FileManager.default.enumerator(
        at: sourceDirectory,
        includingPropertiesForKeys: nil
      )
    )
    let pattern = try NSRegularExpression(
      pattern: #"L10n\.(?:text|format)\(\s*"([^"]+)""#
    )
    var sourceKeys: Set<String> = []

    for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
      let source = try String(contentsOf: fileURL, encoding: .utf8)
      let range = NSRange(source.startIndex..., in: source)
      for match in pattern.matches(in: source, range: range) {
        guard let keyRange = Range(match.range(at: 1), in: source) else { continue }
        sourceKeys.insert(String(source[keyRange]))
      }
    }

    XCTAssertTrue(
      sourceKeys.isSubset(of: localizedKeys),
      "Missing localization keys: \(sourceKeys.subtracting(localizedKeys).sorted())"
    )
  }

  private func strings(language: String) throws -> [String: String] {
    let url =
      repositoryRoot
      .appendingPathComponent("Resources/Localizations")
      .appendingPathComponent("\(language).lproj/Localizable.strings")
    let data = try Data(contentsOf: url)
    return try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: String]
    )
  }

  private var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
