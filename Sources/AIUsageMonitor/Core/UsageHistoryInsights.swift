import Foundation

struct UsageHistoryEvent: Identifiable, Codable, Equatable {
  enum Kind: String, Codable {
    case automaticReset, manualReset, increase, balanceIncrease
    var title: String {
      switch self {
      case .automaticReset: return L10n.text("monitor.eventAutomatic", "自动重置")
      case .manualReset: return L10n.text("monitor.eventManual", "手动重置")
      case .increase: return L10n.text("monitor.eventIncrease", "额度增加（原因未确认）")
      case .balanceIncrease: return L10n.text("monitor.eventBalance", "余额增加（充值或调整）")
      }
    }
  }
  var id = UUID().uuidString
  let providerID: ProviderID
  let metricID: String?
  let accountScope: String?
  let date: Date
  let kind: Kind
}

enum UsageHistoryInsights {
  static let maximumContinuousGap: TimeInterval = 90 * 60

  static func events(previous: ProviderUsageState?, current: ProviderUsageState)
    -> [UsageHistoryEvent]
  {
    guard let previous, previous.status == .connected, current.status == .connected,
      previous.accountScope == current.accountScope
    else { return [] }
    return current.metrics.compactMap { metric in
      guard let old = previous.metrics.first(where: { $0.id == metric.id }),
        old.value.kind == metric.value.kind,
        old.value.currency == metric.value.currency
      else { return nil }
      let value = metric.value.availableFraction ?? metric.value.value
      let oldValue = old.value.availableFraction ?? old.value.value
      let advancedWindow: Bool
      if metric.value.availableFraction != nil, let reset = old.resetsAt,
        let next = metric.resetsAt, reset <= (current.updatedAt ?? .now), next > reset
      {
        advancedWindow = true
      } else {
        advancedWindow = false
      }
      guard advancedWindow || value > oldValue + 0.0001 else { return nil }
      let kind: UsageHistoryEvent.Kind
      if advancedWindow {
        kind = .automaticReset
      } else if metric.value.kind == .balance {
        kind = .balanceIncrease
      } else if metric.value.availableFraction != nil {
        kind = .increase
      } else {
        return nil
      }
      return UsageHistoryEvent(
        providerID: current.id, metricID: metric.id,
        accountScope: current.accountScope, date: current.updatedAt ?? .now, kind: kind)
    }
  }

  static func segments(_ points: [UsageHistoryPoint]) -> [[UsageHistoryPoint]] {
    var result: [[UsageHistoryPoint]] = []
    for group in Dictionary(grouping: points, by: \.seriesID).values {
      var segment: [UsageHistoryPoint] = []
      for point in group.sorted(by: { $0.recordedAt < $1.recordedAt }) {
        if let last = segment.last,
          point.recordedAt.timeIntervalSince(last.recordedAt) > maximumContinuousGap
        {
          result.append(segment)
          segment = []
        }
        segment.append(point)
      }
      if !segment.isEmpty { result.append(segment) }
    }
    return result
  }

  static func estimatedExhaustion(_ points: [UsageHistoryPoint], now: Date = Date()) -> Date? {
    let ordered = points.sorted { $0.recordedAt < $1.recordedAt }
    guard Set(ordered.map(\.seriesID)).count == 1, let last = ordered.last,
      last.scale != .quantity, last.value > 0,
      now.timeIntervalSince(last.recordedAt) >= 0,
      now.timeIntervalSince(last.recordedAt) <= maximumContinuousGap
    else { return nil }
    var tail: [UsageHistoryPoint] = [last]
    for point in ordered.dropLast().reversed() {
      guard let next = tail.first,
        next.recordedAt.timeIntervalSince(point.recordedAt) <= maximumContinuousGap,
        next.value <= point.value,
        last.recordedAt.timeIntervalSince(point.recordedAt) <= 24 * 3_600
      else { break }
      tail.insert(point, at: 0)
    }
    guard tail.count >= 4, let first = tail.first,
      last.recordedAt.timeIntervalSince(first.recordedAt) >= 3_600,
      first.value > last.value
    else { return nil }
    let seconds =
      last.value * last.recordedAt.timeIntervalSince(first.recordedAt) / (first.value - last.value)
    guard seconds.isFinite, seconds <= 90 * 86_400 else { return nil }
    let estimated = last.recordedAt.addingTimeInterval(seconds)
    return estimated > now ? estimated : nil
  }

  static func csv(points: [UsageHistoryPoint], events: [UsageHistoryEvent]) -> String {
    let formatter = ISO8601DateFormatter()
    func cell(_ text: String) -> String {
      // Formula-looking labels are neutralized for spreadsheet applications.
      let value = ["=", "+", "-", "@"].contains(String(text.prefix(1))) ? "'" + text : text
      return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    var rows = ["type,provider,metric,account_scope,time_utc,value,unit,event"]
    rows += points.map { point in
      [
        "sample", point.providerID.rawValue, point.metricLabel, point.accountScope ?? "legacy",
        formatter.string(from: point.recordedAt),
        String(point.value), point.unit ?? "", "",
      ].map(cell).joined(separator: ",")
    }
    rows += events.map { event in
      [
        "event", event.providerID.rawValue, event.metricID ?? "", event.accountScope ?? "legacy",
        formatter.string(from: event.date),
        "", "", event.kind.title,
      ].map(cell).joined(separator: ",")
    }
    return rows.joined(separator: "\n") + "\n"
  }
}

enum UsageEventStore {
  private static var url: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("AI Usage Monitor/usage-events.json")
  }
  static func load() -> [UsageHistoryEvent] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    return (try? JSONDecoder().decode([UsageHistoryEvent].self, from: data)) ?? []
  }
  static func save(_ events: [UsageHistoryEvent]) {
    guard let data = try? JSONEncoder().encode(events) else { return }
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
  }
}
