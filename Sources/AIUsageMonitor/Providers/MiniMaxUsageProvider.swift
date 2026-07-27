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
    let weeklyStatus: Int?
    let endTime: Int64?
    let weeklyEndTime: Int64?

    enum CodingKeys: String, CodingKey {
      case modelName = "model_name"
      case intervalRemainingPercent = "current_interval_remaining_percent"
      case weeklyRemainingPercent = "current_weekly_remaining_percent"
      case weeklyStatus = "current_weekly_status"
      case endTime = "end_time"
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
    guard let general = response.modelRemains.first(where: { $0.modelName == "general" }) else {
      throw HTTPUsageError.invalidResponse
    }

    var metrics: [UsageMetric] = []
    if let percent = general.intervalRemainingPercent {
      metrics.append(
        UsageMetric(
          id: "minimax.5h",
          label: "5 小时",
          value: .availablePercent(percent),
          resetsAt: date(fromMilliseconds: general.endTime),
          resetDescription: nil
        )
      )
    }
    if general.weeklyStatus == 1, let percent = general.weeklyRemainingPercent {
      metrics.append(
        UsageMetric(
          id: "minimax.weekly",
          label: "周期",
          value: .availablePercent(percent),
          resetsAt: date(fromMilliseconds: general.weeklyEndTime),
          resetDescription: nil
        )
      )
    }
    guard !metrics.isEmpty else { throw HTTPUsageError.invalidResponse }
    let summary = metrics.min(by: {
      ($0.value.availableFraction ?? 1) < ($1.value.availableFraction ?? 1)
    })?.value

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
}

enum MiniMaxUsageProviderFactory {
  static func fetch(apiKey: String) async throws -> ProviderUsageState {
    let data = try await HTTPUsageClient.get(
      url: URL(
        string: "https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains"
      )!,
      bearerToken: apiKey
    )
    return try MiniMaxUsageParser.parse(data)
  }

  static func make(apiKey: String) -> PollingUsageProvider {
    PollingUsageProvider(metadata: ProviderCatalog.metadata(for: .minimax)) {
      try await fetch(apiKey: apiKey)
    }
  }
}
