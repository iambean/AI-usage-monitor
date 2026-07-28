import Foundation

enum MiniMaxUsageParser {
  private struct Response: Decodable {
    let modelRemains: [ModelRemain]
    let baseResponse: BaseResponse?

    enum CodingKeys: String, CodingKey {
      case modelRemains = "model_remains"
      case baseResponse = "base_resp"
    }
  }

  private struct BaseResponse: Decodable {
    let statusCode: Int
    let statusMessage: String?

    enum CodingKeys: String, CodingKey {
      case statusCode = "status_code"
      case statusMessage = "status_msg"
    }
  }

  private struct ModelRemain: Decodable {
    let modelName: String
    let intervalRemainingPercent: Double?
    let weeklyRemainingPercent: Double?
    let intervalTotalCount: Double?
    let intervalUsageCount: Double?
    let weeklyTotalCount: Double?
    let weeklyUsageCount: Double?
    let intervalStatus: Int?
    let weeklyStatus: Int?
    let weeklyBoostPermille: Double?
    let startTime: Int64?
    let endTime: Int64?
    let weeklyStartTime: Int64?
    let weeklyEndTime: Int64?

    enum CodingKeys: String, CodingKey {
      case modelName = "model_name"
      case intervalRemainingPercent = "current_interval_remaining_percent"
      case weeklyRemainingPercent = "current_weekly_remaining_percent"
      case intervalTotalCount = "current_interval_total_count"
      case intervalUsageCount = "current_interval_usage_count"
      case weeklyTotalCount = "current_weekly_total_count"
      case weeklyUsageCount = "current_weekly_usage_count"
      case intervalStatus = "current_interval_status"
      case weeklyStatus = "current_weekly_status"
      case weeklyBoostPermille = "weekly_boost_permille"
      case startTime = "start_time"
      case endTime = "end_time"
      case weeklyStartTime = "weekly_start_time"
      case weeklyEndTime = "weekly_end_time"
    }
  }

  static func parse(_ data: Data, now: Date = Date()) throws -> ProviderUsageState {
    let response = try JSONDecoder().decode(Response.self, from: data)
    if let baseResponse = response.baseResponse, baseResponse.statusCode != 0 {
      throw HTTPUsageError.server(
        status: baseResponse.statusCode,
        message: baseResponse.statusMessage
      )
    }
    guard let general = preferredTextModel(response.modelRemains) else {
      throw HTTPUsageError.invalidResponse
    }

    var metrics: [UsageMetric] = []
    if let value = quotaValue(
      explicitPercent: general.intervalRemainingPercent,
      total: general.intervalTotalCount,
      used: general.intervalUsageCount,
      status: general.intervalStatus
    ) {
      metrics.append(
        UsageMetric(
          id: "minimax.5h",
          label: L10n.text("usage.fiveHours", "5 小时"),
          value: value,
          resetsAt: date(fromMilliseconds: general.endTime),
          resetDescription: nil,
          period: .fiveHour
        )
      )
    }
    if let value = quotaValue(
      explicitPercent: boostedWeeklyPercent(general),
      total: general.weeklyTotalCount,
      used: general.weeklyUsageCount,
      status: general.weeklyStatus
    ) {
      metrics.append(
        UsageMetric(
          id: "minimax.weekly",
          label: L10n.text("usage.cycle", "周期"),
          value: value,
          resetsAt: date(fromMilliseconds: general.weeklyEndTime),
          resetDescription: nil,
          period: .weekly
        )
      )
    }
    guard !metrics.isEmpty else { throw HTTPUsageError.invalidResponse }
    let summary = ProviderUsageState.preferredSummary(in: metrics)

    return ProviderUsageState(
      id: .minimax,
      name: "MiniMax",
      symbolName: "m.circle.fill",
      status: .connected,
      summary: summary,
      metrics: metrics,
      updatedAt: now,
      message: nil
    )
  }

  private static func date(fromMilliseconds value: Int64?) -> Date? {
    value.map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) }
  }

  private static func preferredTextModel(_ models: [ModelRemain]) -> ModelRemain? {
    models.first {
      let name = $0.modelName.lowercased()
      return name == "general"
        || name.contains("minimax-m")
        || name.contains("text")
    } ?? models.first(where: { ($0.intervalTotalCount ?? 0) > 0 })
  }

  private static func boostedWeeklyPercent(_ model: ModelRemain) -> Double? {
    guard let percent = model.weeklyRemainingPercent else { return nil }
    let boost = max(model.weeklyBoostPermille ?? 1_000, 0) / 1_000
    return percent * boost
  }

  private static func quotaValue(
    explicitPercent: Double?,
    total: Double?,
    used: Double?,
    status: Int?
  ) -> UsageValue? {
    if status == 3 {
      return .unlimited
    }
    if status == 2 {
      return .availablePercent(0)
    }
    if let explicitPercent {
      return .availablePercent(explicitPercent)
    }
    guard let total, total > 0, let used else {
      return nil
    }
    return .availablePercent((total - used) / total * 100)
  }
}

actor MiniMaxRegionResolver {
  private let preferredRegion: MiniMaxRegion
  private var resolvedRegion: MiniMaxRegion?

  init(preferredRegion: MiniMaxRegion) {
    self.preferredRegion = preferredRegion
  }

  func fetch(apiKey: String) async throws -> ProviderUsageState {
    if let region = resolvedRegion {
      return try await MiniMaxUsageProviderFactory.fetch(
        apiKey: apiKey,
        region: region
      )
    }

    switch preferredRegion {
    case .global, .china:
      let state = try await MiniMaxUsageProviderFactory.fetch(
        apiKey: apiKey,
        region: preferredRegion
      )
      resolvedRegion = preferredRegion
      return state
    case .automatic:
      do {
        let state = try await MiniMaxUsageProviderFactory.fetch(
          apiKey: apiKey,
          region: .global
        )
        resolvedRegion = .global
        return state
      } catch HTTPUsageError.unauthorized {
        let state = try await MiniMaxUsageProviderFactory.fetch(
          apiKey: apiKey,
          region: .china
        )
        resolvedRegion = .china
        return state
      }
    }
  }
}

enum MiniMaxUsageProviderFactory {
  static func fetch(
    apiKey: String,
    region: MiniMaxRegion = .automatic
  ) async throws -> ProviderUsageState {
    if region == .automatic {
      return try await MiniMaxRegionResolver(preferredRegion: .automatic)
        .fetch(apiKey: apiKey)
    }
    let data = try await HTTPUsageClient.get(
      url: endpoint(for: region),
      bearerToken: apiKey
    )
    return try MiniMaxUsageParser.parse(data)
  }

  static func make(
    apiKey: String,
    region: MiniMaxRegion
  ) -> PollingUsageProvider {
    let resolver = MiniMaxRegionResolver(preferredRegion: region)
    return PollingUsageProvider(metadata: ProviderCatalog.metadata(for: .minimax)) {
      try await resolver.fetch(apiKey: apiKey)
    }
  }

  static func endpoint(for region: MiniMaxRegion) -> URL {
    switch region {
    case .automatic, .global:
      return URL(string: "https://api.minimax.io/v1/token_plan/remains")!
    case .china:
      return URL(string: "https://api.minimaxi.com/v1/token_plan/remains")!
    }
  }
}
