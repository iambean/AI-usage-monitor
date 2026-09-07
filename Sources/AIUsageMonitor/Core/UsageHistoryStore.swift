import Foundation

enum UsageHistoryScale: String, Codable, Sendable, Equatable {
  case percent
  case currency
  case quantity
}

struct UsageHistoryPoint: Identifiable, Codable, Sendable, Equatable {
  let providerID: ProviderID
  let metricID: String
  let metricLabel: String
  let recordedAt: Date
  let value: Double
  let scale: UsageHistoryScale
  let unit: String?
  let accountScope: String?

  init(
    providerID: ProviderID, metricID: String, metricLabel: String, recordedAt: Date,
    value: Double, scale: UsageHistoryScale, unit: String?, accountScope: String? = nil
  ) {
    self.providerID = providerID
    self.metricID = metricID
    self.metricLabel = metricLabel
    self.recordedAt = recordedAt
    self.value = value
    self.scale = scale
    self.unit = unit
    self.accountScope = accountScope
  }

  var id: String {
    [
      providerID.rawValue,
      metricID,
      accountScope ?? "",
      String(recordedAt.timeIntervalSince1970),
    ].joined(separator: "|")
  }

  var seriesID: String {
    [providerID.rawValue, metricID, scale.rawValue, unit ?? "", accountScope ?? ""].joined(
      separator: "|")
  }
}

enum UsageHistoryStore {
  static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60
  static let unchangedSampleInterval: TimeInterval = 15 * 60
  static let replacementInterval: TimeInterval = 60
  static let maximumPointCount = 10_000

  private static var historyURL: URL? {
    guard
      let applicationSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      return nil
    }

    return
      applicationSupport
      .appendingPathComponent("AI Usage Monitor", isDirectory: true)
      .appendingPathComponent("usage-history.json", isDirectory: false)
  }

  static func load(now: Date = Date(), retentionDays: Int = 30) -> [UsageHistoryPoint] {
    guard let historyURL,
      let data = try? Data(contentsOf: historyURL),
      let points = try? JSONDecoder().decode([UsageHistoryPoint].self, from: data)
    else {
      return []
    }
    return pruned(points, now: now, retentionDays: retentionDays)
  }

  static func save(_ points: [UsageHistoryPoint]) {
    guard let historyURL,
      let data = try? JSONEncoder().encode(points)
    else {
      return
    }

    let directory = historyURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    try? data.write(to: historyURL, options: .atomic)
  }

  static func record(
    _ state: ProviderUsageState,
    in existingPoints: [UsageHistoryPoint],
    now: Date = Date(),
    retentionDays: Int = 30
  ) -> [UsageHistoryPoint] {
    var result = pruned(existingPoints, now: now, retentionDays: retentionDays)
    guard state.status == .connected else { return result }

    let timestamp = state.updatedAt ?? now
    for metric in state.displayMetrics {
      guard
        let point = historyPoint(
          providerID: state.id,
          metric: metric,
          recordedAt: timestamp,
          accountScope: state.accountScope
        )
      else {
        continue
      }

      if let lastIndex = result.lastIndex(where: { $0.seriesID == point.seriesID }) {
        let previous = result[lastIndex]
        let elapsed = point.recordedAt.timeIntervalSince(previous.recordedAt)
        if elapsed >= 0, elapsed < replacementInterval {
          if previous.value != point.value {
            result[lastIndex] = point
          }
          continue
        }
        if previous.value == point.value,
          elapsed >= 0,
          elapsed < unchangedSampleInterval
        {
          continue
        }
      }
      result.append(point)
    }

    result.sort { $0.recordedAt < $1.recordedAt }
    if result.count > maximumPointCount {
      result = Array(result.suffix(maximumPointCount))
    }
    return result
  }

  static func pruned(
    _ points: [UsageHistoryPoint],
    now: Date = Date(),
    retentionDays: Int = 30
  ) -> [UsageHistoryPoint] {
    let cutoff = now.addingTimeInterval(
      -Double([7, 30, 90].contains(retentionDays) ? retentionDays : 30) * 86_400)
    let retained =
      points
      .filter { $0.recordedAt >= cutoff && $0.recordedAt <= now.addingTimeInterval(60) }
      .sorted { $0.recordedAt < $1.recordedAt }
    return retained.count > maximumPointCount
      ? Array(retained.suffix(maximumPointCount))
      : retained
  }

  private static func historyPoint(
    providerID: ProviderID,
    metric: UsageMetric,
    recordedAt: Date,
    accountScope: String?
  ) -> UsageHistoryPoint? {
    let value: Double
    let scale: UsageHistoryScale
    let unit: String?

    switch metric.value.kind {
    case .availablePercent, .remaining, .usedOfLimit:
      if let availableFraction = metric.value.availableFraction {
        value = availableFraction * 100
        scale = .percent
        unit = "%"
      } else {
        value = metric.value.value
        scale = .quantity
        unit = metric.value.unit
      }
    case .balance, .spent:
      value = metric.value.value
      scale = .currency
      unit = metric.value.currency
    case .unlimited:
      return nil
    }

    guard value.isFinite else { return nil }
    return UsageHistoryPoint(
      providerID: providerID,
      metricID: metric.id,
      metricLabel: metric.label,
      recordedAt: recordedAt,
      value: value,
      scale: scale,
      unit: unit,
      accountScope: accountScope
    )
  }
}

actor UsageHistoryWriter {
  private var latestRevision = 0
  func save(_ points: [UsageHistoryPoint], events: [UsageHistoryEvent], revision: Int) {
    guard revision >= latestRevision else { return }
    latestRevision = revision
    UsageHistoryStore.save(points)
    UsageEventStore.save(events)
  }
}
