import Foundation

struct UsageTrendWindowOption: Identifiable, Equatable {
  static let all = "all-windows"
  let id: String
  let metricID: String
  let title: String
  let scale: UsageHistoryScale
  let unit: String?
}

struct UsageTrendAccountOption: Identifiable, Equatable {
  static let all = "all"
  static let legacy = "legacy"
  let id: String
  let lastRecordedAt: Date
}

struct UsageTrendProjection: Equatable {
  static let empty = UsageTrendProjection(
    windows: [], accounts: [], selectedWindowID: "", selectedAccountID: UsageTrendAccountOption.all,
    chartData: .empty, includesLegacy: false)

  let windows: [UsageTrendWindowOption]
  let accounts: [UsageTrendAccountOption]
  let selectedWindowID: String
  let selectedAccountID: String
  let chartData: UsageTrendChartData
  let includesLegacy: Bool
}

// Build a stable snapshot once per selection/data change. Never rebuild the option list
// inside a per-sample filter or a SwiftUI Picker binding getter.
struct UsageTrendQuery {
  private let providerPoints: [UsageHistoryPoint]
  private let duration: TimeInterval
  private let currentAccountScope: String?
  private let preferredScale: UsageHistoryScale
  private let preferredUnit: String?
  private let now: Date
  let windows: [UsageTrendWindowOption]

  init(
    history: [UsageHistoryPoint], providerID: ProviderID, duration: TimeInterval,
    currentAccountScope: String?, now: Date, preferredMetricID: String? = nil
  ) {
    providerPoints = history.filter {
      $0.providerID == providerID && $0.recordedAt <= now
    }.sorted { $0.recordedAt < $1.recordedAt }
    self.duration = duration
    self.currentAccountScope = currentAccountScope
    preferredScale =
      providerPoints.contains { $0.scale == .percent }
      ? .percent
      : providerPoints.contains { $0.scale == .currency } ? .currency : .quantity
    let scale = preferredScale
    preferredUnit = providerPoints.first { $0.scale == scale }?.unit
    self.now = now
    // Options depend on retained history, not the visible range, so selecting 24h
    // never silently switches to a different window or invalidates a Picker tag.
    let individualWindows: [UsageTrendWindowOption] = Dictionary(
      grouping: providerPoints, by: Self.windowID
    ).compactMap { id, points -> UsageTrendWindowOption? in
      guard let latest = points.last else { return nil }
      return UsageTrendWindowOption(
        id: id, metricID: latest.metricID, title: latest.metricLabel,
        scale: latest.scale, unit: latest.unit)
    }.sorted {
      if ($0.metricID == preferredMetricID) != ($1.metricID == preferredMetricID) {
        return $0.metricID == preferredMetricID
      }
      return $0.title == $1.title ? $0.id < $1.id : $0.title < $1.title
    }
    windows =
      individualWindows.isEmpty
      ? []
      : [
        UsageTrendWindowOption(
          id: UsageTrendWindowOption.all, metricID: "",
          title: L10n.text("trends.allWindows", "全部用量窗口"), scale: preferredScale,
          unit: preferredUnit)
      ] + individualWindows
  }

  static func windowID(_ point: UsageHistoryPoint) -> String {
    [point.providerID.rawValue, point.metricID, point.scale.rawValue, point.unit ?? ""].joined(
      separator: "|")
  }

  func projection(
    selectedWindowID: String = "", selectedAccountID: String = UsageTrendAccountOption.all
  )
    -> UsageTrendProjection
  {
    let windowID =
      windows.contains { $0.id == selectedWindowID }
      ? selectedWindowID : windows.first?.id ?? ""
    let windowPoints = providerPoints.filter {
      windowID == UsageTrendWindowOption.all
        ? $0.scale == preferredScale && $0.unit == preferredUnit : Self.windowID($0) == windowID
    }
    let accounts = Dictionary(
      grouping: windowPoints, by: { $0.accountScope ?? UsageTrendAccountOption.legacy }
    )
    .compactMap { id, points -> UsageTrendAccountOption? in
      points.last.map { UsageTrendAccountOption(id: id, lastRecordedAt: $0.recordedAt) }
    }.sorted {
      if ($0.id == currentAccountScope) != ($1.id == currentAccountScope) {
        return $0.id == currentAccountScope
      }
      return $0.id < $1.id
    }
    let accountID =
      selectedAccountID == UsageTrendAccountOption.all
        || accounts.contains { $0.id == selectedAccountID }
      ? selectedAccountID : UsageTrendAccountOption.all
    let cutoff = now.addingTimeInterval(-duration)
    // Missing account metadata is retained and explicitly labeled, not rewritten
    // as belonging to the currently logged-in account.
    let visible = windowPoints.filter {
      $0.recordedAt >= cutoff
        && (accountID == UsageTrendAccountOption.all
          || ($0.accountScope ?? UsageTrendAccountOption.legacy) == accountID)
    }
    return UsageTrendProjection(
      windows: windows, accounts: accounts,
      selectedWindowID: windowID, selectedAccountID: accountID,
      chartData: UsageTrendChartData(points: visible),
      includesLegacy: visible.contains { $0.accountScope == nil })
  }

  func chartData(selectedID: String = "") -> UsageTrendChartData {
    projection(selectedWindowID: selectedID).chartData
  }
}
