import Foundation

enum ClaudeUsageError: LocalizedError {
  case waitingForData
  case statusLineConflict
  case helperMissing

  var errorDescription: String? {
    switch self {
    case .waitingForData:
      return "采集已启用；使用一次 Claude Code 后会显示用量"
    case .statusLineConflict:
      return "Claude Code 已有状态栏配置，为避免覆盖暂未接入"
    case .helperMissing:
      return "应用内缺少 Claude 用量采集组件"
    }
  }
}

enum ClaudeUsageParser {
  private struct Input: Decodable {
    let rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
      case rateLimits = "rate_limits"
    }
  }

  private struct RateLimits: Decodable {
    let fiveHour: Window?
    let sevenDay: Window?

    enum CodingKeys: String, CodingKey {
      case fiveHour = "five_hour"
      case sevenDay = "seven_day"
    }
  }

  private struct Window: Decodable {
    let usedPercentage: Double
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
      case usedPercentage = "used_percentage"
      case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      usedPercentage = try container.decode(Double.self, forKey: .usedPercentage)

      if let epoch = try? container.decode(Double.self, forKey: .resetsAt) {
        resetsAt = Date(timeIntervalSince1970: epoch)
      } else if let text = try? container.decode(String.self, forKey: .resetsAt) {
        resetsAt =
          ISO8601DateFormatter().date(from: text)
          ?? Double(text).map(Date.init(timeIntervalSince1970:))
      } else {
        resetsAt = nil
      }
    }
  }

  static func parse(_ data: Data, now: Date = Date()) throws -> ProviderUsageState {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let input = try decoder.decode(Input.self, from: data)
    guard let rateLimits = input.rateLimits else { throw ClaudeUsageError.waitingForData }

    let entries: [(String, String, Window?)] = [
      ("5h", "5 小时", rateLimits.fiveHour),
      ("weekly", "周期", rateLimits.sevenDay),
    ]
    let metrics = entries.compactMap { id, label, window -> UsageMetric? in
      guard let window else { return nil }
      return UsageMetric(
        id: "claude.\(id)",
        label: label,
        value: .availablePercent(100 - window.usedPercentage),
        resetsAt: window.resetsAt,
        resetDescription: nil
      )
    }
    guard !metrics.isEmpty else { throw ClaudeUsageError.waitingForData }
    let summary = metrics.min(by: {
      ($0.value.availableFraction ?? 1) < ($1.value.availableFraction ?? 1)
    })?.value

    return ProviderUsageState(
      id: .claude,
      name: "Claude Code",
      symbolName: "a.circle.fill",
      status: .connected,
      summary: summary,
      metrics: metrics,
      updatedAt: now,
      message: nil
    )
  }
}

enum ClaudeUsageStorage {
  static var cacheURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("AI Usage Monitor", isDirectory: true)
      .appendingPathComponent("claude-usage.json")
  }
}

enum ClaudeStatusLineInstaller {
  static func install() throws {
    let helperURL = Bundle.main.bundleURL
      .appendingPathComponent("Contents/Helpers/AIUsageCollector")
    guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
      throw ClaudeUsageError.helperMissing
    }

    let settingsURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/settings.json")
    var settings: [String: Any] = [:]
    if let data = try? Data(contentsOf: settingsURL),
      let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      settings = existing
    }

    if let statusLine = settings["statusLine"] as? [String: Any] {
      let command = statusLine["command"] as? String ?? ""
      guard command.contains("AIUsageCollector") else {
        throw ClaudeUsageError.statusLineConflict
      }
    }

    let escapedPath = helperURL.path.replacingOccurrences(of: "'", with: "'\\''")
    settings["statusLine"] = [
      "type": "command",
      "command": "'\(escapedPath)'",
    ]
    let directory = settingsURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try JSONSerialization.data(
      withJSONObject: settings,
      options: [.prettyPrinted, .sortedKeys]
    )
    try data.write(to: settingsURL, options: .atomic)
  }

  static func uninstallIfOwned() {
    let settingsURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/settings.json")
    guard let data = try? Data(contentsOf: settingsURL),
      var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let statusLine = settings["statusLine"] as? [String: Any],
      let command = statusLine["command"] as? String,
      command.contains("AIUsageCollector")
    else {
      return
    }
    settings.removeValue(forKey: "statusLine")
    guard
      let updated = try? JSONSerialization.data(
        withJSONObject: settings,
        options: [.prettyPrinted, .sortedKeys]
      )
    else {
      return
    }
    try? updated.write(to: settingsURL, options: .atomic)
  }
}

enum ClaudeUsageProviderFactory {
  static func make() -> PollingUsageProvider {
    PollingUsageProvider(
      metadata: ProviderCatalog.metadata(for: .claude),
      refreshInterval: 120
    ) {
      guard let data = try? Data(contentsOf: ClaudeUsageStorage.cacheURL) else {
        throw ClaudeUsageError.waitingForData
      }
      return try ClaudeUsageParser.parse(data)
    }
  }
}
