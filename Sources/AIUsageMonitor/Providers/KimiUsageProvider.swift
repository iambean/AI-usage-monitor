import Foundation

enum KimiUsageError: LocalizedError {
  case credentialsNotFound
  case invalidCredentials
  case noUsage

  var errorDescription: String? {
    switch self {
    case .credentialsNotFound:
      return "未找到 Kimi Code 登录信息，请先登录 Kimi Code"
    case .invalidCredentials:
      return "Kimi Code 登录已过期，请运行一次 Kimi Code 重新登录"
    case .noUsage:
      return "Kimi Code 暂未返回套餐用量"
    }
  }
}

enum KimiCredentialStore {
  private struct Credentials: Decodable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
      case accessToken = "access_token"
    }
  }

  static func accessToken(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) throws -> String {
    let url = homeDirectory
      .appendingPathComponent(".kimi-code/credentials/kimi-code.json")
    guard let data = try? Data(contentsOf: url) else {
      throw KimiUsageError.credentialsNotFound
    }
    guard let credentials = try? JSONDecoder().decode(Credentials.self, from: data),
      !credentials.accessToken.isEmpty
    else {
      throw KimiUsageError.invalidCredentials
    }
    return credentials.accessToken
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
    let used: String
    let remaining: String
    let resetTime: String?
  }

  static func parse(_ data: Data, now: Date = Date()) throws -> ProviderUsageState {
    let response = try JSONDecoder().decode(Response.self, from: data)
    var metrics: [UsageMetric] = []

    if let usage = response.usage, let metric = metric(
      id: "kimi.period",
      label: "周期",
      quota: usage
    ) {
      metrics.append(metric)
    }

    metrics.append(
      contentsOf: response.limits.compactMap { limit in
        metric(
          id: "kimi.\(limit.window.duration).\(limit.window.timeUnit)",
          label: windowLabel(limit.window),
          quota: limit.detail
        )
      }
    )

    guard !metrics.isEmpty else { throw KimiUsageError.noUsage }
    let summary = metrics.min(by: {
      ($0.value.availableFraction ?? 1) < ($1.value.availableFraction ?? 1)
    })?.value

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

  private static func metric(id: String, label: String, quota: Quota) -> UsageMetric? {
    guard let total = Double(quota.limit), let remaining = Double(quota.remaining), total > 0 else {
      return nil
    }
    return UsageMetric(
      id: id,
      label: label,
      value: .availablePercent((remaining / total * 1_000).rounded() / 10),
      resetsAt: quota.resetTime.flatMap(parseDate),
      resetDescription: nil
    )
  }

  private static func windowLabel(_ window: Window) -> String {
    switch (window.duration, window.timeUnit) {
    case (300, "TIME_UNIT_MINUTE"):
      return "5 小时"
    case (_, "TIME_UNIT_MINUTE") where window.duration.isMultiple(of: 60):
      return "\(window.duration / 60) 小时"
    default:
      return "短期"
    }
  }

  private static func parseDate(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
}

enum KimiUsageProviderFactory {
  static func fetch() async throws -> ProviderUsageState {
    let accessToken = try KimiCredentialStore.accessToken()
    do {
      let data = try await HTTPUsageClient.get(
        url: URL(string: "https://api.kimi.com/coding/v1/usages")!,
        bearerToken: accessToken
      )
      return try KimiUsageParser.parse(data)
    } catch HTTPUsageError.unauthorized {
      throw KimiUsageError.invalidCredentials
    }
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
