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
  case upToDate
  case available(version: String, url: URL)
}

enum AppUpdateStatus: Equatable {
  case idle
  case checking
  case upToDate
  case available(version: String, url: URL)
  case failed
}

actor UpdateChecker {
  typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  private static let latestReleaseURL = URL(
    string: "https://api.github.com/repos/iambean/codex-usage-monitor/releases/latest"
  )!
  private static let minimumInterval: TimeInterval = 24 * 60 * 60
  private static let lastAttemptKey = "update-last-attempt"
  private static let latestVersionKey = "update-latest-version"
  private static let latestURLKey = "update-latest-url"

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
    var request = URLRequest(url: Self.latestReleaseURL)
    request.timeoutInterval = 15
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("AI-Usage-Update-Checker", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await send(request)
    guard let response = response as? HTTPURLResponse else {
      throw UpdateCheckError.invalidResponse
    }
    if response.statusCode == 404 {
      defaults.removeObject(forKey: Self.latestVersionKey)
      defaults.removeObject(forKey: Self.latestURLKey)
      return .upToDate
    }
    guard (200...299).contains(response.statusCode) else {
      throw UpdateCheckError.invalidResponse
    }
    let release = try JSONDecoder().decode(Release.self, from: data)
    defaults.set(release.tagName, forKey: Self.latestVersionKey)
    defaults.set(release.htmlURL.absoluteString, forKey: Self.latestURLKey)
    return result(
      currentVersion: currentVersion,
      latestVersion: release.tagName,
      url: release.htmlURL
    )
  }

  private func cachedResult(currentVersion: String) -> UpdateCheckResult {
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

  private struct Release: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
      case tagName = "tag_name"
      case htmlURL = "html_url"
    }
  }
}

enum UpdateCheckError: LocalizedError {
  case invalidResponse

  var errorDescription: String? {
    L10n.text("update.checkFailed", "检查更新失败")
  }
}
