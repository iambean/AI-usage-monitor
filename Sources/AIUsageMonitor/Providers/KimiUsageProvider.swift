import Foundation

enum KimiUsageError: LocalizedError {
  case credentialsNotFound
  case invalidCredentials
  case noUsage

  var errorDescription: String? {
    switch self {
    case .credentialsNotFound:
      return L10n.text(
        "error.kimiCredentialsNotFound",
        "未找到 Kimi Code 登录信息，请先登录 Kimi Code"
      )
    case .invalidCredentials:
      return L10n.text(
        "error.kimiCredentialsExpired",
        "Kimi Code 登录已过期，请运行一次 Kimi Code 重新登录"
      )
    case .noUsage:
      return L10n.text(
        "error.kimiNoUsage",
        "Kimi Code 暂未返回套餐用量"
      )
    }
  }
}

struct KimiCredentials: Codable, Equatable {
  let accessToken: String
  let refreshToken: String
  let expiresAt: TimeInterval
  let scope: String
  let tokenType: String
  let expiresIn: TimeInterval

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresAt = "expires_at"
    case scope
    case tokenType = "token_type"
    case expiresIn = "expires_in"
  }
}

enum KimiOAuthError: LocalizedError {
  case unauthorized
  case invalidResponse
  case server(status: Int, message: String?)
  case credentialWriteFailed
  case refreshBusy

  var errorDescription: String? {
    switch self {
    case .unauthorized:
      return L10n.text(
        "error.kimiUnauthorized",
        "Kimi Code 登录已失效，请运行一次 Kimi Code 重新登录"
      )
    case .invalidResponse:
      return L10n.text(
        "error.kimiRefreshInvalidResponse",
        "Kimi Code 登录续期返回了无法识别的数据"
      )
    case .server(let status, let message):
      if let message, !message.isEmpty {
        return L10n.format(
          "error.kimiRefreshHTTPWithMessage",
          "Kimi Code 登录续期失败（HTTP %d）：%@",
          status,
          message
        )
      }
      return L10n.format(
        "error.kimiRefreshHTTP",
        "Kimi Code 登录续期失败（HTTP %d）",
        status
      )
    case .credentialWriteFailed:
      return L10n.text(
        "error.kimiCredentialWrite",
        "无法更新 Kimi Code 登录信息"
      )
    case .refreshBusy:
      return L10n.text(
        "error.kimiRefreshBusy",
        "Kimi Code 正在更新登录信息，请稍后刷新"
      )
    }
  }
}

enum KimiCredentialStore {
  typealias Refresh = (KimiCredentials, URL, Date) async throws -> KimiCredentials

  static func load(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) throws -> KimiCredentials {
    let url = credentialsURL(homeDirectory: homeDirectory)
    guard let data = try? Data(contentsOf: url) else {
      throw KimiUsageError.credentialsNotFound
    }
    guard let credentials = try? JSONDecoder().decode(KimiCredentials.self, from: data),
      !credentials.accessToken.isEmpty
    else {
      throw KimiUsageError.invalidCredentials
    }
    return credentials
  }

  static func accessToken(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    now: Date = Date(),
    forceRefresh: Bool = false,
    refresh: @escaping Refresh = { credentials, _, now in
      try await KimiOAuthClient.refresh(credentials, now: now)
    }
  ) async throws -> String {
    let credentials = try load(homeDirectory: homeDirectory)
    guard forceRefresh || shouldRefresh(credentials, now: now) else {
      return credentials.accessToken
    }

    return try await KimiRefreshLock.withLock(homeDirectory: homeDirectory) {
      let current = try load(homeDirectory: homeDirectory)
      if forceRefresh {
        if current != credentials {
          return current.accessToken
        }
      } else if !shouldRefresh(current, now: now) {
        return current.accessToken
      }
      guard !current.refreshToken.isEmpty else {
        throw KimiOAuthError.unauthorized
      }

      let refreshed = try await refresh(current, homeDirectory, now)
      try save(refreshed, homeDirectory: homeDirectory)
      return refreshed.accessToken
    }
  }

  static func save(
    _ credentials: KimiCredentials,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) throws {
    let url = credentialsURL(homeDirectory: homeDirectory)
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      var data = try encoder.encode(credentials)
      data.append(0x0A)
      try data.write(to: url, options: .atomic)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: url.path
      )
    } catch {
      throw KimiOAuthError.credentialWriteFailed
    }
  }

  private static func credentialsURL(homeDirectory: URL) -> URL {
    homeDirectory.appendingPathComponent(".kimi-code/credentials/kimi-code.json")
  }

  private static func shouldRefresh(_ credentials: KimiCredentials, now: Date) -> Bool {
    guard credentials.expiresAt > 0 else { return false }
    let threshold = max(300, credentials.expiresIn * 0.5)
    return credentials.expiresAt - now.timeIntervalSince1970 < threshold
  }
}

enum KimiRefreshLock {
  private static let retryCount = 30
  private static let retryNanoseconds: UInt64 = 500_000_000
  private static let staleInterval: TimeInterval = 10

  static func withLock<T>(
    homeDirectory: URL,
    operation: () async throws -> T
  ) async throws -> T {
    let lockURL = try await acquire(homeDirectory: homeDirectory)
    let heartbeat = Task {
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: 2_000_000_000)
        } catch {
          return
        }
        try? FileManager.default.setAttributes(
          [.modificationDate: Date()],
          ofItemAtPath: lockURL.path
        )
      }
    }
    defer {
      heartbeat.cancel()
      try? FileManager.default.removeItem(at: lockURL)
    }
    return try await operation()
  }

  private static func acquire(homeDirectory: URL) async throws -> URL {
    let directory = homeDirectory.appendingPathComponent(".kimi-code/oauth", isDirectory: true)
    let sentinel = directory.appendingPathComponent("kimi-code")
    let lockURL = directory.appendingPathComponent("kimi-code.lock", isDirectory: true)

    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    if !FileManager.default.fileExists(atPath: sentinel.path) {
      _ = FileManager.default.createFile(
        atPath: sentinel.path,
        contents: Data(),
        attributes: [.posixPermissions: 0o600]
      )
    }

    for _ in 0..<retryCount {
      do {
        try FileManager.default.createDirectory(
          at: lockURL,
          withIntermediateDirectories: false,
          attributes: [.posixPermissions: 0o700]
        )
        return lockURL
      } catch {
        if isStale(lockURL) {
          try? FileManager.default.removeItem(at: lockURL)
          continue
        }
        try await Task.sleep(nanoseconds: retryNanoseconds)
      }
    }
    throw KimiOAuthError.refreshBusy
  }

  private static func isStale(_ lockURL: URL, now: Date = Date()) -> Bool {
    guard
      let attributes = try? FileManager.default.attributesOfItem(atPath: lockURL.path),
      let modifiedAt = attributes[.modificationDate] as? Date
    else {
      return false
    }
    return now.timeIntervalSince(modifiedAt) > staleInterval
  }
}

enum KimiOAuthClient {
  typealias Send = (URLRequest) async throws -> (Data, URLResponse)

  private static let clientID = "17e5f671-d194-4dfb-9706-5516cb48c098"
  private static let tokenURL = URL(string: "https://auth.kimi.com/api/oauth/token")!

  private struct Response: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
    let scope: String?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
      case accessToken = "access_token"
      case refreshToken = "refresh_token"
      case expiresIn = "expires_in"
      case scope
      case tokenType = "token_type"
    }
  }

  static func refresh(
    _ credentials: KimiCredentials,
    now: Date = Date(),
    send: @escaping Send = { request in
      try await URLSession.shared.data(for: request)
    }
  ) async throws -> KimiCredentials {
    var components = URLComponents()
    components.queryItems = [
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "grant_type", value: "refresh_token"),
      URLQueryItem(name: "refresh_token", value: credentials.refreshToken),
    ]

    var request = URLRequest(url: tokenURL)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
    request.setValue(
      "application/x-www-form-urlencoded",
      forHTTPHeaderField: "Content-Type"
    )
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response) = try await send(request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw KimiOAuthError.invalidResponse
    }
    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
      throw KimiOAuthError.unauthorized
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      let message =
        payload?["error_description"] as? String
        ?? payload?["message"] as? String
        ?? payload?["error"] as? String
      if payload?["error"] as? String == "invalid_grant" {
        throw KimiOAuthError.unauthorized
      }
      throw KimiOAuthError.server(status: httpResponse.statusCode, message: message)
    }

    guard let value = try? JSONDecoder().decode(Response.self, from: data),
      !value.accessToken.isEmpty,
      !value.refreshToken.isEmpty,
      value.expiresIn > 0
    else {
      throw KimiOAuthError.invalidResponse
    }
    return KimiCredentials(
      accessToken: value.accessToken,
      refreshToken: value.refreshToken,
      expiresAt: floor(now.timeIntervalSince1970 + value.expiresIn),
      scope: value.scope ?? credentials.scope,
      tokenType: value.tokenType ?? credentials.tokenType,
      expiresIn: value.expiresIn
    )
  }
}

enum KimiUsageParser {
  private struct Response: Decodable {
    let usage: Quota?
    let limits: [Limit]
  }

  private struct Limit: Decodable {
    let window: Window
    let detail: Quota
  }

  private struct Window: Decodable {
    let duration: Int
    let timeUnit: String
  }

  private struct Quota: Decodable {
    let limit: String
    let used: String?
    let remaining: String?
    let resetTime: String?
  }

  static func parse(_ data: Data, now: Date = Date()) throws -> ProviderUsageState {
    let response = try JSONDecoder().decode(Response.self, from: data)
    var metrics: [UsageMetric] = []

    if let usage = response.usage,
      let metric = metric(
        id: "kimi.period",
        label: L10n.text("usage.cycle", "周期"),
        quota: usage,
        period: .weekly
      )
    {
      metrics.append(metric)
    }

    metrics.append(
      contentsOf: response.limits.compactMap { limit in
        metric(
          id: "kimi.\(limit.window.duration).\(limit.window.timeUnit)",
          label: windowLabel(limit.window),
          quota: limit.detail,
          period: windowPeriod(limit.window)
        )
      }
    )

    guard !metrics.isEmpty else { throw KimiUsageError.noUsage }
    let summary = ProviderUsageState.preferredSummary(in: metrics)

    return ProviderUsageState(
      id: .kimi,
      name: "Kimi Code",
      symbolName: "moon.circle.fill",
      status: .connected,
      summary: summary,
      metrics: metrics,
      updatedAt: now,
      message: nil
    )
  }

  private static func metric(
    id: String,
    label: String,
    quota: Quota,
    period: UsagePeriodKind
  ) -> UsageMetric? {
    guard let total = Double(quota.limit), total > 0 else {
      return nil
    }
    let remaining: Double
    if let rawRemaining = quota.remaining, let parsedRemaining = Double(rawRemaining) {
      remaining = parsedRemaining
    } else if let rawUsed = quota.used, let used = Double(rawUsed) {
      remaining = max(total - used, 0)
    } else {
      return nil
    }
    return UsageMetric(
      id: id,
      label: label,
      value: .availablePercent((remaining / total * 1_000).rounded() / 10),
      resetsAt: quota.resetTime.flatMap(parseDate),
      resetDescription: nil,
      period: period
    )
  }

  private static func windowLabel(_ window: Window) -> String {
    switch (window.duration, window.timeUnit) {
    case (300, "TIME_UNIT_MINUTE"):
      return L10n.text("usage.fiveHours", "5 小时")
    case (_, "TIME_UNIT_MINUTE") where window.duration.isMultiple(of: 60):
      return L10n.format("usage.hours", "%d 小时", window.duration / 60)
    default:
      return L10n.text("usage.shortTerm", "短期")
    }
  }

  private static func windowPeriod(_ window: Window) -> UsagePeriodKind {
    if window.duration == 300, window.timeUnit == "TIME_UNIT_MINUTE" {
      return .fiveHour
    }
    return .other
  }

  private static func parseDate(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
}

enum KimiUsageProviderFactory {
  static func fetch() async throws -> ProviderUsageState {
    do {
      return try await fetch(forceRefresh: false)
    } catch HTTPUsageError.unauthorized {
      do {
        return try await fetch(forceRefresh: true)
      } catch HTTPUsageError.unauthorized {
        throw KimiUsageError.invalidCredentials
      } catch KimiOAuthError.unauthorized {
        throw KimiUsageError.invalidCredentials
      }
    } catch KimiOAuthError.unauthorized {
      throw KimiUsageError.invalidCredentials
    }
  }

  private static func fetch(forceRefresh: Bool) async throws -> ProviderUsageState {
    let accessToken = try await KimiCredentialStore.accessToken(
      forceRefresh: forceRefresh
    )
    let data = try await HTTPUsageClient.get(
      url: URL(string: "https://api.kimi.com/coding/v1/usages")!,
      bearerToken: accessToken
    )
    return try KimiUsageParser.parse(data)
  }

  static func make() -> PollingUsageProvider {
    PollingUsageProvider(
      metadata: ProviderCatalog.metadata(for: .kimi),
      refreshInterval: 900
    ) {
      try await fetch()
    }
  }
}
