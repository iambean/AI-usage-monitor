import Foundation

enum ProviderID: String, CaseIterable, Codable, Sendable {
  case codex
  case claude
  case cursor
  case kimi
  case minimax
  case deepseek
  case qoder
  case ark
  case aliyun
  case tencent
  case glm
}

enum ProviderAvailability: Sendable, Equatable {
  case available
  case unavailable(String)
}

enum ProviderConfigurationKind: Sendable, Equatable {
  case automatic
  case apiKey
  case qoderTeams
}

enum ProviderSupportTier: String, Sendable, Equatable {
  case stable
  case compatible
  case unavailable
}

struct ProviderMetadata: Identifiable, Sendable, Equatable {
  let id: ProviderID
  let name: String
  let symbolName: String
  let detail: String
  let availability: ProviderAvailability
  let configurationKind: ProviderConfigurationKind
  let supportTier: ProviderSupportTier
}

enum ProviderCatalog {
  static var all: [ProviderMetadata] { [
    ProviderMetadata(
      id: .codex,
      name: "Codex",
      symbolName: "c.circle.fill",
      detail: L10n.text("provider.codex.detail", "自动读取 Codex CLI"),
      availability: .available,
      configurationKind: .automatic,
      supportTier: .compatible
    ),
    ProviderMetadata(
      id: .claude,
      name: "Claude Code",
      symbolName: "a.circle.fill",
      detail: L10n.text(
        "provider.claude.detail",
        "自动读取 Claude Code 状态栏数据"
      ),
      availability: .available,
      configurationKind: .automatic,
      supportTier: .compatible
    ),
    ProviderMetadata(
      id: .cursor,
      name: "Cursor",
      symbolName: "cursorarrow.rays",
      detail: L10n.text(
        "provider.cursor.detail",
        "Teams 版需要管理员 Admin API Key"
      ),
      availability: .available,
      configurationKind: .apiKey,
      supportTier: .stable
    ),
    ProviderMetadata(
      id: .kimi,
      name: "Kimi Code",
      symbolName: "moon.circle.fill",
      detail: L10n.text("provider.kimi.detail", "自动读取 Kimi Code /usage"),
      availability: .available,
      configurationKind: .automatic,
      supportTier: .compatible
    ),
    ProviderMetadata(
      id: .minimax,
      name: "MiniMax",
      symbolName: "m.circle.fill",
      detail: L10n.text("provider.minimax.detail", "需要 Token Plan 订阅 Key"),
      availability: .available,
      configurationKind: .apiKey,
      supportTier: .stable
    ),
    ProviderMetadata(
      id: .deepseek,
      name: "DeepSeek",
      symbolName: "d.circle.fill",
      detail: L10n.text("provider.deepseek.detail", "需要 DeepSeek API Key"),
      availability: .available,
      configurationKind: .apiKey,
      supportTier: .stable
    ),
    ProviderMetadata(
      id: .qoder,
      name: "Qoder Teams",
      symbolName: "q.circle.fill",
      detail: L10n.text("provider.qoder.detail", "需要 Teams OpenAPI 配置"),
      availability: .available,
      configurationKind: .qoderTeams,
      supportTier: .stable
    ),
    ProviderMetadata(
      id: .ark,
      name: L10n.text("provider.ark.name", "火山方舟 Ark"),
      symbolName: "flame.circle.fill",
      detail: L10n.text(
        "provider.codingPlan.unavailableReason",
        "等待官方稳定用量查询接口"
      ),
      availability: .unavailable(
        L10n.text(
          "provider.codingPlan.unavailableReason",
          "等待官方稳定用量查询接口"
        )
      ),
      configurationKind: .automatic,
      supportTier: .unavailable
    ),
    ProviderMetadata(
      id: .aliyun,
      name: L10n.text("provider.aliyun.name", "阿里云百炼"),
      symbolName: "cloud.circle.fill",
      detail: L10n.text(
        "provider.codingPlan.unavailableReason",
        "等待官方稳定用量查询接口"
      ),
      availability: .unavailable(
        L10n.text(
          "provider.codingPlan.unavailableReason",
          "等待官方稳定用量查询接口"
        )
      ),
      configurationKind: .automatic,
      supportTier: .unavailable
    ),
    ProviderMetadata(
      id: .tencent,
      name: L10n.text("provider.tencent.name", "腾讯云 Coding Plan"),
      symbolName: "cloud.fill",
      detail: L10n.text(
        "provider.codingPlan.unavailableReason",
        "等待官方稳定用量查询接口"
      ),
      availability: .unavailable(
        L10n.text(
          "provider.codingPlan.unavailableReason",
          "等待官方稳定用量查询接口"
        )
      ),
      configurationKind: .automatic,
      supportTier: .unavailable
    ),
    ProviderMetadata(
      id: .glm,
      name: "GLM Coding Plan",
      symbolName: "g.circle.fill",
      detail: L10n.text("status.temporarilyUnavailable", "暂不可用"),
      availability: .unavailable(
        L10n.text(
          "provider.glm.unavailableReason",
          "官方暂未提供稳定的用量查询接口"
        )
      ),
      configurationKind: .automatic,
      supportTier: .unavailable
    ),
  ] }

  static func metadata(for id: ProviderID) -> ProviderMetadata {
    all.first(where: { $0.id == id })!
  }
}

enum ProviderConnectionStatus: String, Codable, Sendable {
  case loading
  case connected
  case stale
  case needsConfiguration
  case error
}

enum UsageValueKind: String, Codable, Sendable {
  case availablePercent
  case remaining
  case balance
  case spent
  case usedOfLimit
  case unlimited
}

struct UsageValue: Codable, Sendable, Equatable {
  let kind: UsageValueKind
  let value: Double
  let total: Double?
  let unit: String?
  let currency: String?

  static func availablePercent(_ value: Double) -> UsageValue {
    UsageValue(
      kind: .availablePercent,
      value: value.clamped(to: 0...100),
      total: 100,
      unit: "%",
      currency: nil
    )
  }

  static func remaining(_ value: Double, total: Double?, unit: String) -> UsageValue {
    UsageValue(kind: .remaining, value: value, total: total, unit: unit, currency: nil)
  }

  static func balance(_ value: Double, currency: String) -> UsageValue {
    UsageValue(kind: .balance, value: value, total: nil, unit: nil, currency: currency)
  }

  static func spent(_ value: Double, currency: String) -> UsageValue {
    UsageValue(kind: .spent, value: value, total: nil, unit: nil, currency: currency)
  }

  static func used(_ value: Double, of total: Double, unit: String) -> UsageValue {
    UsageValue(kind: .usedOfLimit, value: value, total: total, unit: unit, currency: nil)
  }

  static var unlimited: UsageValue {
    UsageValue(kind: .unlimited, value: 1, total: nil, unit: nil, currency: nil)
  }

  var availableFraction: Double? {
    switch kind {
    case .availablePercent:
      return (value / 100).clamped(to: 0...1)
    case .remaining:
      guard let total, total > 0 else { return nil }
      return (value / total).clamped(to: 0...1)
    case .usedOfLimit:
      guard let total, total > 0 else { return nil }
      return ((total - value) / total).clamped(to: 0...1)
    case .balance, .spent:
      return nil
    case .unlimited:
      return 1
    }
  }

  var displayText: String {
    switch kind {
    case .availablePercent:
      return "\(Self.number(value))%"
    case .remaining:
      if let total {
        return "\(Self.number(value))/\(Self.number(total)) \(unit ?? "")".trimmingCharacters(
          in: .whitespaces
        )
      }
      return "\(Self.number(value)) \(unit ?? "")".trimmingCharacters(in: .whitespaces)
    case .balance:
      return "\(Self.currencySymbol(currency))\(Self.money(value))"
    case .spent:
      return "\(Self.currencySymbol(currency))\(Self.money(value))"
    case .usedOfLimit:
      guard let total else { return "\(Self.number(value)) \(unit ?? "")" }
      return "\(Self.number(value))/\(Self.number(total)) \(unit ?? "")".trimmingCharacters(
        in: .whitespaces
      )
    case .unlimited:
      return "∞"
    }
  }

  var compactDisplayText: String {
    switch kind {
    case .usedOfLimit:
      guard let total else { return Self.number(value) }
      return "\(Self.number(value))/\(Self.number(total))"
    default:
      return displayText
    }
  }

  var caption: String {
    switch kind {
    case .availablePercent, .remaining, .unlimited:
      return L10n.text("usage.remaining", "剩余")
    case .balance:
      return L10n.text("usage.balance", "余额")
    case .spent, .usedOfLimit:
      return L10n.text("usage.used", "已用")
    }
  }

  private static func number(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.locale = L10n.locale
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = value.rounded() == value ? 0 : 1
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
  }

  private static func money(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.locale = L10n.locale
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
  }

  private static func currencySymbol(_ currency: String?) -> String {
    switch currency?.uppercased() {
    case "CNY":
      return "¥"
    case "USD":
      return "$"
    default:
      return currency.map { "\($0) " } ?? ""
    }
  }
}

enum UsagePeriodKind: String, Codable, Sendable, Equatable {
  case fiveHour
  case weekly
  case monthly
  case other
}

struct UsageMetric: Identifiable, Codable, Sendable, Equatable {
  let id: String
  let label: String
  let value: UsageValue
  let resetsAt: Date?
  let resetDescription: String?
  let period: UsagePeriodKind?

  init(
    id: String,
    label: String,
    value: UsageValue,
    resetsAt: Date?,
    resetDescription: String?,
    period: UsagePeriodKind? = nil
  ) {
    self.id = id
    self.label = label
    self.value = value
    self.resetsAt = resetsAt
    self.resetDescription = resetDescription
    self.period = period
  }
}

struct ProviderMessageAction: Codable, Sendable, Equatable {
  let title: String
  let url: URL
}

struct ProviderUsageState: Identifiable, Codable, Sendable, Equatable {
  let id: ProviderID
  let name: String
  let symbolName: String
  var status: ProviderConnectionStatus
  var summary: UsageValue?
  var metrics: [UsageMetric]
  var updatedAt: Date?
  var message: String?
  var recoverySuggestion: String?
  var messageAction: ProviderMessageAction?

  init(
    id: ProviderID,
    name: String,
    symbolName: String,
    status: ProviderConnectionStatus,
    summary: UsageValue?,
    metrics: [UsageMetric],
    updatedAt: Date?,
    message: String?,
    recoverySuggestion: String? = nil,
    messageAction: ProviderMessageAction? = nil
  ) {
    self.id = id
    self.name = name
    self.symbolName = symbolName
    self.status = status
    self.summary = summary
    self.metrics = metrics
    self.updatedAt = updatedAt
    self.message = message
    self.recoverySuggestion = recoverySuggestion
    self.messageAction = messageAction
  }

  var defaultSummary: UsageValue? {
    guard status == .connected || status == .stale else { return nil }
    return Self.preferredSummary(in: metrics) ?? summary
  }

  var displayMetrics: [UsageMetric] {
    metrics.enumerated()
      .sorted { lhs, rhs in
        let lhsPriority = Self.displayPriority(Self.periodKind(for: lhs.element))
        let rhsPriority = Self.displayPriority(Self.periodKind(for: rhs.element))
        return lhsPriority == rhsPriority
          ? lhs.offset < rhs.offset
          : lhsPriority < rhsPriority
      }
      .map(\.element)
  }

  static func preferredSummary(in metrics: [UsageMetric]) -> UsageValue? {
    metrics.first(where: { periodKind(for: $0) == .fiveHour })?.value
      ?? metrics.first(where: { periodKind(for: $0) == .weekly })?.value
      ?? metrics.first?.value
  }

  private static func periodKind(for metric: UsageMetric) -> UsagePeriodKind? {
    if let period = metric.period {
      return period
    }

    let id = metric.id.lowercased()
    if id.contains(".5h") || id.contains(".300.") {
      return .fiveHour
    }
    if id.contains("weekly") || id.hasSuffix(".secondary") || id == "kimi.period" {
      return .weekly
    }
    return nil
  }

  private static func displayPriority(_ period: UsagePeriodKind?) -> Int {
    switch period {
    case .fiveHour:
      return 0
    case .weekly:
      return 1
    case .monthly:
      return 2
    case .other, nil:
      return 3
    }
  }

  func failed(
    status: ProviderConnectionStatus = .error,
    message: String,
    recoverySuggestion: String
  ) -> ProviderUsageState {
    var state = self
    state.status = status
    state.summary = nil
    state.metrics = []
    state.updatedAt = nil
    state.message = message
    state.recoverySuggestion = recoverySuggestion
    state.messageAction = nil
    return state
  }

  static func loading(_ id: ProviderID) -> ProviderUsageState {
    let metadata = ProviderCatalog.metadata(for: id)
    return ProviderUsageState(
      id: id,
      name: metadata.name,
      symbolName: metadata.symbolName,
      status: .loading,
      summary: nil,
      metrics: [],
      updatedAt: nil,
      message: L10n.text("status.connectingNow", "正在连接"),
      recoverySuggestion: nil
    )
  }
}

extension Comparable {
  fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
