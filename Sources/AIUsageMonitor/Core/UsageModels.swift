import Foundation

enum ProviderID: String, CaseIterable, Codable, Sendable {
  case codex
  case claude
  case kimi
  case minimax
  case deepseek
  case qoder
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

struct ProviderMetadata: Identifiable, Sendable, Equatable {
  let id: ProviderID
  let name: String
  let symbolName: String
  let detail: String
  let availability: ProviderAvailability
  let configurationKind: ProviderConfigurationKind
}

enum ProviderCatalog {
  static let all: [ProviderMetadata] = [
    ProviderMetadata(
      id: .codex,
      name: "Codex",
      symbolName: "c.circle.fill",
      detail: "自动读取 Codex CLI",
      availability: .available,
      configurationKind: .automatic
    ),
    ProviderMetadata(
      id: .claude,
      name: "Claude Code",
      symbolName: "a.circle.fill",
      detail: "自动读取 Claude Code 状态栏数据",
      availability: .available,
      configurationKind: .automatic
    ),
    ProviderMetadata(
      id: .kimi,
      name: "Kimi Code",
      symbolName: "moon.circle.fill",
      detail: "自动读取 Kimi Code /usage",
      availability: .available,
      configurationKind: .automatic
    ),
    ProviderMetadata(
      id: .minimax,
      name: "MiniMax",
      symbolName: "m.circle.fill",
      detail: "需要 Token Plan 订阅 Key",
      availability: .available,
      configurationKind: .apiKey
    ),
    ProviderMetadata(
      id: .deepseek,
      name: "DeepSeek",
      symbolName: "d.circle.fill",
      detail: "需要 DeepSeek API Key",
      availability: .available,
      configurationKind: .apiKey
    ),
    ProviderMetadata(
      id: .qoder,
      name: "Qoder Teams",
      symbolName: "q.circle.fill",
      detail: "需要 Teams OpenAPI 配置",
      availability: .available,
      configurationKind: .qoderTeams
    ),
    ProviderMetadata(
      id: .glm,
      name: "GLM Coding Plan",
      symbolName: "g.circle.fill",
      detail: "暂不可用",
      availability: .unavailable("官方暂未提供稳定的用量查询接口"),
      configurationKind: .automatic
    ),
  ]

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
  case usedOfLimit
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

  static func used(_ value: Double, of total: Double, unit: String) -> UsageValue {
    UsageValue(kind: .usedOfLimit, value: value, total: total, unit: unit, currency: nil)
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
    case .balance:
      return nil
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
    case .usedOfLimit:
      guard let total else { return "\(Self.number(value)) \(unit ?? "")" }
      return "\(Self.number(value))/\(Self.number(total)) \(unit ?? "")".trimmingCharacters(
        in: .whitespaces
      )
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
    case .availablePercent, .remaining:
      return "剩余"
    case .balance:
      return "余额"
    case .usedOfLimit:
      return "已用"
    }
  }

  private static func number(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = value.rounded() == value ? 0 : 1
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
  }

  private static func money(_ value: Double) -> String {
    let formatter = NumberFormatter()
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

struct UsageMetric: Identifiable, Codable, Sendable, Equatable {
  let id: String
  let label: String
  let value: UsageValue
  let resetsAt: Date?
  let resetDescription: String?
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
      message: "正在连接"
    )
  }
}

extension Comparable {
  fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
