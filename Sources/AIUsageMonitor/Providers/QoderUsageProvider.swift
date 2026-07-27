import Foundation

enum QoderUsageParser {
  private struct Response: Decodable {
    let planQuota: Quota?
    let resourcePackageQuota: Quota?
    let totalQuota: Quota?
    let sharedQuota: Quota?
    let nextResetAt: String?
    let status: String?
  }

  private struct Quota: Decodable {
    let quotaSummary: Summary
  }

  private struct Summary: Decodable {
    let usedValue: Double
    let limitValue: Double
    let unit: String
  }

  static func parse(_ data: Data, now: Date = Date()) throws -> ProviderUsageState {
    let response = try JSONDecoder().decode(Response.self, from: data)
    let resetDate = response.nextResetAt.flatMap(ISO8601DateFormatter().date(from:))
    let entries: [(String, String, Quota?)] = [
      ("total", "总额度", response.totalQuota),
      ("plan", "套餐额度", response.planQuota),
      ("package", "资源包", response.resourcePackageQuota),
      ("shared", "团队共享", response.sharedQuota),
    ]
    let metrics = entries.compactMap { id, label, quota -> UsageMetric? in
      guard let summary = quota?.quotaSummary else { return nil }
      return UsageMetric(
        id: "qoder.\(id)",
        label: label,
        value: .used(summary.usedValue, of: summary.limitValue, unit: summary.unit),
        resetsAt: resetDate,
        resetDescription: nil
      )
    }

    guard let summary = metrics.first?.value else {
      throw HTTPUsageError.invalidResponse
    }

    return ProviderUsageState(
      id: .qoder,
      name: "Qoder Teams",
      symbolName: "q.circle.fill",
      status: .connected,
      summary: summary,
      metrics: metrics,
      updatedAt: now,
      message: response.status == "restricted" ? "已达到团队用量上限" : nil
    )
  }
}

enum QoderUsageProviderFactory {
  static func fetch(
    apiKey: String,
    configuration: QoderConfiguration
  ) async throws -> ProviderUsageState {
    let organizationID = configuration.organizationID.addingPercentEncoding(
      withAllowedCharacters: .urlPathAllowed
    ) ?? configuration.organizationID
    let memberID = configuration.memberID.addingPercentEncoding(
      withAllowedCharacters: .urlPathAllowed
    ) ?? configuration.memberID
    let url = URL(
      string:
        "https://api.qoder.com/v1/organizations/\(organizationID)/members/\(memberID)/quota"
    )!
    let data = try await HTTPUsageClient.get(url: url, bearerToken: apiKey)
    return try QoderUsageParser.parse(data)
  }

  static func make(apiKey: String, configuration: QoderConfiguration) -> PollingUsageProvider {
    PollingUsageProvider(metadata: ProviderCatalog.metadata(for: .qoder)) {
      try await fetch(apiKey: apiKey, configuration: configuration)
    }
  }
}
