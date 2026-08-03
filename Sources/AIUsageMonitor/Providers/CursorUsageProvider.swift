import Foundation

struct CursorTeamSpendPage: Sendable, Equatable {
  let spendCents: Double
  let subscriptionCycleStart: Date?
  let totalMembers: Int
  let totalPages: Int
}

enum CursorUsageParser {
  private struct Response: Decodable {
    let teamMemberSpend: [MemberSpend]
    let subscriptionCycleStart: Double?
    let totalMembers: Int
    let totalPages: Int
  }

  private struct MemberSpend: Decodable {
    let spendCents: Double
  }

  static func parsePage(_ data: Data) throws -> CursorTeamSpendPage {
    let response = try JSONDecoder().decode(Response.self, from: data)
    return CursorTeamSpendPage(
      spendCents: response.teamMemberSpend.reduce(0) { $0 + $1.spendCents },
      subscriptionCycleStart: response.subscriptionCycleStart.map(dateFromEpoch),
      totalMembers: response.totalMembers,
      totalPages: max(response.totalPages, 1)
    )
  }

  static func makeState(
    pages: [CursorTeamSpendPage],
    now: Date = Date()
  ) throws -> ProviderUsageState {
    guard let firstPage = pages.first else {
      throw HTTPUsageError.invalidResponse
    }
    let spend = pages.reduce(0) { $0 + $1.spendCents } / 100
    let nextCycle = firstPage.subscriptionCycleStart.flatMap {
      Calendar(identifier: .gregorian).date(byAdding: .month, value: 1, to: $0)
    }
    let summary = UsageValue.spent(spend, currency: "USD")
    let metrics = [
      UsageMetric(
        id: "cursor.teamSpend",
        label: L10n.text("usage.teamSpend", "本周期团队支出"),
        value: summary,
        resetsAt: nextCycle,
        resetDescription: nil,
        period: .monthly
      ),
      UsageMetric(
        id: "cursor.members",
        label: L10n.text("usage.teamMembers", "团队成员"),
        value: .remaining(
          Double(firstPage.totalMembers),
          total: nil,
          unit: L10n.text("usage.membersUnit", "人")
        ),
        resetsAt: nil,
        resetDescription: nil
      ),
    ]

    return ProviderUsageState(
      id: .cursor,
      name: "Cursor",
      symbolName: "cursorarrow.rays",
      status: .connected,
      summary: summary,
      metrics: metrics,
      updatedAt: now,
      message: nil
    )
  }

  private static func dateFromEpoch(_ value: Double) -> Date {
    let seconds = value > 10_000_000_000 ? value / 1_000 : value
    return Date(timeIntervalSince1970: seconds)
  }
}

enum CursorUsageProviderFactory {
  static let endpoint = URL(string: "https://api.cursor.com/teams/spend")!

  static func fetch(apiKey: String) async throws -> ProviderUsageState {
    let firstPage = try await fetchPage(apiKey: apiKey, page: 1)
    var pages = [firstPage]
    if firstPage.totalPages > 1 {
      for page in 2...firstPage.totalPages {
        pages.append(try await fetchPage(apiKey: apiKey, page: page))
      }
    }
    return try CursorUsageParser.makeState(pages: pages)
  }

  static func makeTeams(apiKey: String) -> PollingUsageProvider {
    PollingUsageProvider(
      metadata: ProviderCatalog.metadata(for: .cursor),
      refreshInterval: 900
    ) {
      try await fetch(apiKey: apiKey)
    }
  }

  static func makePersonal() -> PollingUsageProvider {
    PollingUsageProvider(
      metadata: ProviderCatalog.metadata(for: .cursor),
      refreshInterval: 86_400
    ) {
      personalState()
    }
  }

  static func personalState(now: Date = Date()) -> ProviderUsageState {
    ProviderUsageState(
      id: .cursor,
      name: "Cursor",
      symbolName: "cursorarrow.rays",
      status: .connected,
      summary: nil,
      metrics: [],
      updatedAt: now,
      message: L10n.text(
        "provider.cursor.personalWebOnly",
        "个人版暂未提供公开用量 API，"
      ),
      messageAction: ProviderMessageAction(
        title: L10n.text("usage.openUsagePage", "请打开 Usage 页面"),
        url: ProviderUsageDestination.url(for: .cursor)
      )
    )
  }

  private static func fetchPage(
    apiKey: String,
    page: Int
  ) async throws -> CursorTeamSpendPage {
    let body = try JSONSerialization.data(
      withJSONObject: ["page": page, "pageSize": 100]
    )
    let data = try await HTTPUsageClient.post(
      url: endpoint,
      basicUsername: apiKey,
      jsonBody: body
    )
    return try CursorUsageParser.parsePage(data)
  }
}
