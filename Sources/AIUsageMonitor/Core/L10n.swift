import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
  case system
  case simplifiedChinese = "zh-Hans"
  case english = "en"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .system:
      return L10n.text("settings.language.system", "跟随系统")
    case .simplifiedChinese:
      return L10n.text("settings.language.chinese", "简体中文")
    case .english:
      return L10n.text("settings.language.english", "English")
    }
  }

  var locale: Locale {
    switch self {
    case .system:
      return .current
    case .simplifiedChinese:
      return Locale(identifier: "zh-Hans")
    case .english:
      return Locale(identifier: "en")
    }
  }

  fileprivate var localizationResource: String? {
    switch self {
    case .system:
      return nil
    case .simplifiedChinese:
      return "zh-Hans"
    case .english:
      return "en"
    }
  }
}

enum AppLanguageStore {
  static let key = "app-language"

  static func load(defaults: UserDefaults = .standard) -> AppLanguage {
    guard
      let rawValue = defaults.string(forKey: key),
      let language = AppLanguage(rawValue: rawValue)
    else {
      return .system
    }
    return language
  }

  static func save(
    _ language: AppLanguage,
    defaults: UserDefaults = .standard
  ) {
    defaults.set(language.rawValue, forKey: key)
  }
}

enum L10n {
  static var locale: Locale {
    AppLanguageStore.load().locale
  }

  static func text(_ key: String, _ fallback: String) -> String {
    localizedString(
      key,
      fallback: fallback,
      language: AppLanguageStore.load()
    )
  }

  static func format(
    _ key: String,
    _ fallback: String,
    _ arguments: CVarArg...
  ) -> String {
    String(
      format: text(key, fallback),
      locale: locale,
      arguments: arguments
    )
  }

  static func localizedString(
    _ key: String,
    fallback: String,
    language: AppLanguage,
    bundle: Bundle = .main
  ) -> String {
    let localizedBundle: Bundle
    if let resource = language.localizationResource,
      let path = bundle.path(forResource: resource, ofType: "lproj"),
      let languageBundle = Bundle(path: path)
    {
      localizedBundle = languageBundle
    } else {
      localizedBundle = bundle
    }

    return localizedBundle.localizedString(
      forKey: key,
      value: fallback,
      table: nil
    )
  }
}
