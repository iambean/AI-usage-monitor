import Foundation

struct AppVersion: Comparable, Equatable {
  private let components: [Int]

  init(_ value: String) {
    components =
      value
      .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
      .split(separator: ".")
      .map { component in
        Int(component.prefix(while: \.isNumber)) ?? 0
      }
  }

  static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
    let count = max(lhs.components.count, rhs.components.count)
    for index in 0..<count {
      let left = index < lhs.components.count ? lhs.components[index] : 0
      let right = index < rhs.components.count ? rhs.components[index] : 0
      if left != right {
        return left < right
      }
    }
    return false
  }

  static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
    !(lhs < rhs) && !(rhs < lhs)
  }
}

enum UpdateCheckResult: Sendable, Equatable {
  case skipped
  case noRelease
  case upToDate
  case available(version: String, url: URL)
}

enum AppUpdateStatus: Equatable {
  case idle
  case checking
  case noRelease
  case upToDate
  case available(version: String, url: URL)
  case failed
}

actor UpdateChecker {
  typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  private static let appcastURL = URL(
    string: "https://raw.githubusercontent.com/iambean/AI-usage-monitor/main/appcast.xml"
  )!
  private static let minimumInterval: TimeInterval = 24 * 60 * 60
  private static let lastAttemptKey = "update-last-attempt"
  private static let latestVersionKey = "update-latest-version"
  private static let latestURLKey = "update-latest-url"
  private static let noReleaseKey = "update-no-release"

  private let defaults: UserDefaults
  private let send: Send

  init(
    defaults: UserDefaults = .standard,
    send: @escaping Send = { request in
      try await URLSession.shared.data(for: request)
    }
  ) {
    self.defaults = defaults
    self.send = send
  }

  func check(
    currentVersion: String,
    force: Bool,
    now: Date = Date()
  ) async throws -> UpdateCheckResult {
    if !force,
      let lastAttempt = defaults.object(forKey: Self.lastAttemptKey) as? Date,
      now.timeIntervalSince(lastAttempt) < Self.minimumInterval
    {
      return cachedResult(currentVersion: currentVersion)
    }

    defaults.set(now, forKey: Self.lastAttemptKey)
    var request = URLRequest(url: Self.appcastURL)
    request.timeoutInterval = 15
    request.setValue(
      "application/rss+xml, application/xml;q=0.9, text/xml;q=0.8",
      forHTTPHeaderField: "Accept"
    )
    request.setValue("AI-Usage-Update-Checker", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await send(request)
    guard let response = response as? HTTPURLResponse else {
      throw UpdateCheckError.invalidResponse
    }
    if response.statusCode == 404 {
      cacheNoRelease()
      return .noRelease
    }
    guard (200...299).contains(response.statusCode) else {
      throw UpdateCheckError.invalidResponse
    }
    guard let release = try AppcastReleaseParser.latestRelease(from: data) else {
      cacheNoRelease()
      return .noRelease
    }
    defaults.removeObject(forKey: Self.noReleaseKey)
    defaults.set(release.version, forKey: Self.latestVersionKey)
    defaults.set(release.url.absoluteString, forKey: Self.latestURLKey)
    return result(
      currentVersion: currentVersion,
      latestVersion: release.version,
      url: release.url
    )
  }

  private func cacheNoRelease() {
    defaults.removeObject(forKey: Self.latestVersionKey)
    defaults.removeObject(forKey: Self.latestURLKey)
    defaults.set(true, forKey: Self.noReleaseKey)
  }

  private func cachedResult(currentVersion: String) -> UpdateCheckResult {
    if defaults.bool(forKey: Self.noReleaseKey) {
      return .noRelease
    }
    guard
      let version = defaults.string(forKey: Self.latestVersionKey),
      let rawURL = defaults.string(forKey: Self.latestURLKey),
      let url = URL(string: rawURL)
    else {
      return .skipped
    }
    return result(
      currentVersion: currentVersion,
      latestVersion: version,
      url: url
    )
  }

  private func result(
    currentVersion: String,
    latestVersion: String,
    url: URL
  ) -> UpdateCheckResult {
    if AppVersion(currentVersion) < AppVersion(latestVersion) {
      return .available(version: latestVersion, url: url)
    }
    return .upToDate
  }

}

private struct AppcastRelease {
  let version: String
  let url: URL
}

private final class AppcastReleaseParser: NSObject, XMLParserDelegate {
  private var releases: [AppcastRelease] = []
  private var isInsideItem = false
  private var currentText = ""
  private var currentVersion: String?
  private var currentLink: URL?
  private var currentEnclosureURL: URL?

  static func latestRelease(from data: Data) throws -> AppcastRelease? {
    let delegate = AppcastReleaseParser()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    guard parser.parse() else {
      throw UpdateCheckError.invalidResponse
    }
    return delegate.releases.max {
      AppVersion($0.version) < AppVersion($1.version)
    }
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    currentText = ""

    if elementName == "item" {
      isInsideItem = true
      currentVersion = nil
      currentLink = nil
      currentEnclosureURL = nil
    } else if isInsideItem, elementName == "enclosure" {
      currentEnclosureURL = attributeDict["url"].flatMap(URL.init(string:))
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    currentText += string
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

    if isInsideItem, elementName.hasSuffix("shortVersionString") {
      currentVersion = text
    } else if isInsideItem, elementName == "link" {
      currentLink = URL(string: text)
    } else if elementName == "item" {
      if let version = currentVersion,
        let url = currentLink ?? currentEnclosureURL
      {
        releases.append(AppcastRelease(version: version, url: url))
      }
      isInsideItem = false
    }

    currentText = ""
  }
}

enum UpdateCheckError: LocalizedError {
  case invalidResponse

  var errorDescription: String? {
    L10n.text("update.checkFailed", "检查更新失败")
  }
}
