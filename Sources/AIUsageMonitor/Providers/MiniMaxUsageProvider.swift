import Foundation

enum MiniMaxAPIError: LocalizedError, Equatable {
  case service(code: Int, message: String?)
  case missingQuota
  case invalidResponse

  var isAuthenticationFailure: Bool {
    if case .service(let code, _) = self { return [1004, 2049].contains(code) }
    return false
  }

  var errorDescription: String? {
    switch self {
    case .service(let code, let message):
      return L10n.format(
        "error.minimaxService", "MiniMax 返回错误（%@）：%@", String(code),
        message.map { DiagnosticSanitizer.text($0) }
          ?? L10n.text("error.invalidResponse", "服务返回了无法识别的数据"))
    case .missingQuota:
      return L10n.text("error.minimaxMissingQuota", "MiniMax 未返回可用的 Token Plan 用量。")
    case .invalidResponse:
      return L10n.text("error.minimaxInvalidResponse", "MiniMax 返回的用量格式暂不兼容，请稍后重试。")
    }
  }

  var recoverySuggestion: String? {
    if isAuthenticationFailure || self == .missingQuota {
      return L10n.text(
        "recovery.minimaxTokenPlan", "请确认 Key 与服务区域匹配。订阅 Key 查询套餐用量，sk-api- 开头的普通 API Key 查询余额。")
    }
    return L10n.text("recovery.minimaxService", "请根据 MiniMax 返回的详情检查订阅状态，或稍后重试。")
  }
}

enum MiniMaxUsageParser {
  private struct Envelope: Decodable {
    let baseResponse: BaseResponse?
    enum CodingKeys: String, CodingKey { case baseResponse = "base_resp" }
  }

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
    try validateEnvelope(data)
    let decoder = JSONDecoder()
    let response: Response
    do { response = try decoder.decode(Response.self, from: data) } catch {
      throw MiniMaxAPIError.invalidResponse
    }
    guard let general = preferredTextModel(response.modelRemains) else {
      throw MiniMaxAPIError.missingQuota
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
    guard !metrics.isEmpty else { throw MiniMaxAPIError.missingQuota }
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

  private struct BalanceResponse: Decodable {
    let amount: Double
    let currency: String?
    enum CodingKeys: String, CodingKey {
      case amount = "available_amount"
      case currency
    }
    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      if let value = try? container.decode(Double.self, forKey: .amount) {
        amount = value
      } else {
        let raw = try container.decode(String.self, forKey: .amount)
        guard let value = Double(raw) else { throw MiniMaxAPIError.invalidResponse }
        amount = value
      }
      currency = try container.decodeIfPresent(String.self, forKey: .currency)
    }
  }

  static func parseBalance(
    _ data: Data, defaultCurrency: String? = nil, now: Date = Date()
  ) throws -> ProviderUsageState {
    try validateEnvelope(data)
    guard let response = try? JSONDecoder().decode(BalanceResponse.self, from: data),
      response.amount.isFinite
    else {
      throw MiniMaxAPIError.invalidResponse
    }
    let currency = response.currency?.trimmingCharacters(in: .whitespacesAndNewlines)
    let value = UsageValue(
      kind: .balance, value: response.amount, total: nil, unit: nil,
      currency: currency?.isEmpty == false ? currency : defaultCurrency)
    return ProviderUsageState(
      id: .minimax, name: "MiniMax", symbolName: "m.circle.fill", status: .connected,
      summary: value,
      metrics: [
        UsageMetric(
          id: "minimax.balance", label: L10n.text("usage.apiBalance", "API 可用余额"),
          value: value, resetsAt: nil, resetDescription: nil)
      ], updatedAt: now, message: nil)
  }

  private static func validateEnvelope(_ data: Data) throws {
    let decoder = JSONDecoder()
    let envelope: Envelope
    do { envelope = try decoder.decode(Envelope.self, from: data) } catch {
      throw MiniMaxAPIError.invalidResponse
    }
    // Error responses omit model_remains, and can still have HTTP status 200.
    if let status = envelope.baseResponse, status.statusCode != 0 {
      throw MiniMaxAPIError.service(code: status.statusCode, message: status.statusMessage)
    }
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
  typealias Fetch = @Sendable (String, MiniMaxRegion) async throws -> ProviderUsageState
  private let fetchRegion: Fetch
  private let preferredRegion: MiniMaxRegion
  private var resolvedRegion: MiniMaxRegion?

  init(
    preferredRegion: MiniMaxRegion,
    fetch: @escaping Fetch = { key, region in
      try await MiniMaxUsageProviderFactory.fetch(apiKey: key, region: region)
    }
  ) {
    self.preferredRegion = preferredRegion
    self.fetchRegion = fetch
  }

  func fetch(apiKey: String) async throws -> ProviderUsageState {
    if let region = resolvedRegion { return try await fetchRegion(apiKey, region) }
    switch preferredRegion {
    case .global, .china:
      let state = try await fetchRegion(apiKey, preferredRegion)
      resolvedRegion = preferredRegion
      return state
    case .automatic:
      do {
        let state = try await fetchRegion(apiKey, .global)
        resolvedRegion = .global
        return state
      } catch {
        let isHTTPAuthenticationFailure: Bool
        if case HTTPUsageError.unauthorized = error {
          isHTTPAuthenticationFailure = true
        } else if case HTTPUsageError.server(let status, _) = error,
          [400, 401, 403, 404].contains(status)
        {
          // The overseas balance endpoint reports a China-key mismatch as HTTP 400 / params error.
          isHTTPAuthenticationFailure = true
        } else {
          isHTTPAuthenticationFailure = false
        }
        guard
          isHTTPAuthenticationFailure
            || (error as? MiniMaxAPIError)?.isAuthenticationFailure == true
        else { throw error }
        let state = try await fetchRegion(apiKey, .china)
        resolvedRegion = .china
        return state
      }
    }
  }

}

enum MiniMaxUsageProviderFactory {
  typealias Request = @Sendable (URL, String) async throws -> Data

  static func usesAccountBalance(apiKey: String) -> Bool {
    apiKey.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("sk-api-")
  }

  static func fetch(
    apiKey: String,
    region: MiniMaxRegion = .automatic,
    request: @escaping Request = { url, key in
      try await MiniMaxHTTPClient.get(url: url, apiKey: key)
    }
  ) async throws -> ProviderUsageState {
    if region == .automatic {
      return try await MiniMaxRegionResolver(
        preferredRegion: .automatic,
        fetch: { key, region in
          try await fetch(apiKey: key, region: region, request: request)
        }
      ).fetch(apiKey: apiKey)
    }
    let balance = usesAccountBalance(apiKey: apiKey)
    let url = balance ? balanceEndpoint(for: region) : endpoint(for: region)
    let data = try await request(url, apiKey)
    // Automatic detection has resolved to the endpoint that actually accepted the key here.
    // International pay-as-you-go pricing: https://platform.minimax.io/docs/guides/pricing-paygo
    return try balance
      ? MiniMaxUsageParser.parseBalance(data, defaultCurrency: region == .china ? "CNY" : "USD")
      : MiniMaxUsageParser.parse(data)
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

  static func balanceEndpoint(for region: MiniMaxRegion) -> URL {
    let host = region == .china ? "api.minimaxi.com" : "api.minimax.io"
    return URL(string: "https://\(host)/account/query_balance")!
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
