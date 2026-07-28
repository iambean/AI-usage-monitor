import Foundation

enum DeepSeekUsageParser {
  private struct Response: Decodable {
    let isAvailable: Bool
    let balanceInfos: [Balance]

    enum CodingKeys: String, CodingKey {
      case isAvailable = "is_available"
      case balanceInfos = "balance_infos"
    }
  }

  private struct Balance: Decodable {
    let currency: String
    let totalBalance: String
    let grantedBalance: String
    let toppedUpBalance: String

    enum CodingKeys: String, CodingKey {
      case currency
      case totalBalance = "total_balance"
      case grantedBalance = "granted_balance"
      case toppedUpBalance = "topped_up_balance"
    }
  }

  static func parse(_ data: Data, now: Date = Date()) throws -> ProviderUsageState {
    let response = try JSONDecoder().decode(Response.self, from: data)
    let metrics = response.balanceInfos.compactMap { item -> UsageMetric? in
      guard let total = Double(item.totalBalance) else { return nil }
      return UsageMetric(
        id: "deepseek.\(item.currency.lowercased())",
        label: L10n.format(
          "usage.availableBalance",
          "%@ 可用余额",
          item.currency
        ),
        value: .balance(total, currency: item.currency),
        resetsAt: nil,
        resetDescription: nil
      )
    }

    guard let summary = metrics.first?.value else {
      throw HTTPUsageError.invalidResponse
    }

    return ProviderUsageState(
      id: .deepseek,
      name: "DeepSeek",
      symbolName: "d.circle.fill",
      status: .connected,
      summary: summary,
      metrics: metrics,
      updatedAt: now,
      message: response.isAvailable
        ? nil
        : L10n.text(
          "error.balanceUnavailable",
          "当前余额不可用于 API 调用"
        )
    )
  }
}

enum DeepSeekUsageProviderFactory {
  static func fetch(apiKey: String) async throws -> ProviderUsageState {
    let data = try await HTTPUsageClient.get(
      url: URL(string: "https://api.deepseek.com/user/balance")!,
      bearerToken: apiKey
    )
    return try DeepSeekUsageParser.parse(data)
  }

  static func make(apiKey: String) -> PollingUsageProvider {
    PollingUsageProvider(metadata: ProviderCatalog.metadata(for: .deepseek)) {
      try await fetch(apiKey: apiKey)
    }
  }
}
