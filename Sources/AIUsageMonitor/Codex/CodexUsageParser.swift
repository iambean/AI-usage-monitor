import Foundation

enum CodexUsageParser {
  static func parse(result: JSONValue, now: Date = Date()) throws -> ProviderUsageState {
    guard let root = result.objectValue else {
      throw CodexClientError.rpc("Codex 返回了无法识别的用量数据")
    }

    let snapshots = rateLimitSnapshots(from: root)
    let hasMultipleLimits = snapshots.count > 1
    let metrics = snapshots.flatMap { limitID, snapshot in
      parseMetrics(
        snapshot: snapshot,
        limitID: limitID,
        includeLimitName: hasMultipleLimits
      )
    }

    guard !metrics.isEmpty else {
      throw CodexClientError.rpc("Codex 暂未返回可用的用量窗口")
    }

    return ProviderUsageState(
      id: .codex,
      name: "Codex",
      symbolName: "c.circle.fill",
      status: .connected,
      summary: metrics.min(by: {
        ($0.value.availableFraction ?? 1) < ($1.value.availableFraction ?? 1)
      })?.value,
      metrics: metrics,
      updatedAt: now,
      message: nil
    )
  }

  static func parseNotification(
    params: JSONValue,
    merging current: ProviderUsageState?,
    now: Date = Date()
  ) -> ProviderUsageState? {
    guard let rateLimits = params["rateLimits"] else { return nil }

    let wrapped: JSONValue = .object(["rateLimits": rateLimits])
    guard let update = try? parse(result: wrapped, now: now) else { return nil }
    guard var current else { return update }

    for metric in update.metrics {
      if let index = current.metrics.firstIndex(where: { $0.id == metric.id }) {
        current.metrics[index] = metric
      } else {
        current.metrics.append(metric)
      }
    }

    current.status = .connected
    current.summary = current.metrics.min(by: {
      ($0.value.availableFraction ?? 1) < ($1.value.availableFraction ?? 1)
    })?.value
    current.updatedAt = now
    current.message = nil
    return current
  }

  private static func rateLimitSnapshots(
    from root: [String: JSONValue]
  ) -> [(String, [String: JSONValue])] {
    if let byID = root["rateLimitsByLimitId"]?.objectValue, !byID.isEmpty {
      return
        byID
        .compactMap { key, value in
          value.objectValue.map { (key, $0) }
        }
        .sorted { $0.0 < $1.0 }
    }

    if let snapshot = root["rateLimits"]?.objectValue {
      let limitID = snapshot["limitId"]?.stringValue ?? "codex"
      return [(limitID, snapshot)]
    }

    return []
  }

  private static func parseMetrics(
    snapshot: [String: JSONValue],
    limitID: String,
    includeLimitName: Bool
  ) -> [UsageMetric] {
    let limitName = snapshot["limitName"]?.stringValue
    return ["primary", "secondary"].compactMap { windowKey in
      guard let window = snapshot[windowKey]?.objectValue,
        let usedPercent = window["usedPercent"]?.doubleValue
      else {
        return nil
      }

      let duration = window["windowDurationMins"]?.intValue
      let baseLabel = windowLabel(for: duration, fallbackKey: windowKey)
      let label: String
      if includeLimitName, let limitName, !limitName.isEmpty {
        label = "\(condensedLimitName(limitName)) · \(baseLabel)"
      } else {
        label = baseLabel
      }

      let available = Int((100 - usedPercent).rounded())
        .clamped(to: 0...100)
      let resetsAt = window["resetsAt"]?.doubleValue.map {
        Date(timeIntervalSince1970: $0)
      }

      return UsageMetric(
        id: "\(limitID).\(windowKey)",
        label: label,
        value: .availablePercent(Double(available)),
        resetsAt: resetsAt,
        resetDescription: nil
      )
    }
  }

  private static func windowLabel(for durationMinutes: Int?, fallbackKey: String) -> String {
    guard let durationMinutes else {
      return fallbackKey == "primary" ? "短期" : "周期"
    }

    switch durationMinutes {
    case 300:
      return "5 小时"
    case 10_080:
      return "周期"
    case 43_200:
      return "月度"
    default:
      if durationMinutes.isMultiple(of: 1_440) {
        return "\(durationMinutes / 1_440) 天"
      }
      if durationMinutes.isMultiple(of: 60) {
        return "\(durationMinutes / 60) 小时"
      }
      return "\(durationMinutes) 分钟"
    }
  }

  private static func condensedLimitName(_ name: String) -> String {
    if name.localizedCaseInsensitiveContains("spark") {
      return "Spark"
    }
    return name
  }
}

extension Comparable {
  fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
