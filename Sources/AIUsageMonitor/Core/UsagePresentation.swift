import Foundation

extension ProviderUsageState {
  var summaryMetric: UsageMetric? {
    if id == .codex { return codexDefaultMetric }
    return displayMetrics.first
  }

  func selectedMetric(_ metricID: String?) -> UsageMetric? {
    guard status == .connected || status == .stale else { return nil }
    guard let metricID, !metricID.isEmpty else { return summaryMetric }
    return metrics.first { $0.id == metricID }
  }

  var metricGroups: [(name: String?, metrics: [UsageMetric])] {
    guard id == .codex else { return [(nil, displayMetrics)] }
    let keys = Array(Set(metrics.map { String($0.id.split(separator: ".").first ?? "") })).sorted()
    return keys.map { key in
      let group = displayMetrics.filter { $0.id.hasPrefix(key + ".") }
      let name = key == "codex" ? "Default" : key == "codex_bengalfox" ? "Spark" : key
      return (name, group)
    }
  }

  func handlingFailure(_ error: Error) -> ProviderUsageState {
    let message = error.localizedDescription
    let recovery = ProviderRecoverySuggestion.text(for: error, providerID: id)
    guard UsageFailurePolicy.isTransient(error), !metrics.isEmpty, updatedAt != nil else {
      return failed(message: message, recoverySuggestion: recovery)
    }
    var state = self
    state.status = .stale
    state.message = message
    state.recoverySuggestion = recovery
    state.messageAction = nil
    return state
  }
}

enum UsageFailurePolicy {
  static func isTransient(_ error: Error) -> Bool {
    if let error = error as? URLError {
      return [
        .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
        .dnsLookupFailed, .notConnectedToInternet, .internationalRoamingOff,
        .dataNotAllowed,
      ].contains(error.code)
    }
    if case HTTPUsageError.server(let status, _) = error { return status >= 500 || status == 429 }
    if case MiniMaxAPIError.service(let code, _) = error {
      return [1001, 1002, 1013].contains(code)
    }
    if let error = error as? CodexClientError {
      switch error {
      case .processExited, .missingInput, .timeout: return true
      case .rpc(let message):
        let text = message.lowercased()
        guard !text.contains("401"), !text.contains("403"), !text.contains("unauthorized") else {
          return false
        }
        return ["timeout", "timed out", "network", "connection", "error sending request"].contains {
          text.contains($0)
        }
      default: return false
      }
    }
    return false
  }
}

enum UsagePresentation {
  static func caption(_ metric: UsageMetric, providerID: ProviderID) -> String {
    if metric.value.kind == .balance {
      guard let currency = metric.value.currency else {
        return L10n.text("usage.balanceCurrencyUnknown", "余额 · 币种未提供")
      }
      return currency + " " + metric.value.caption
    }
    let name = providerID == .codex && metric.id.hasPrefix("codex.") ? "Default · " : ""
    return name + metric.label + " · " + metric.value.caption
  }

  static func resetText(_ metric: UsageMetric, now: Date = Date()) -> String? {
    guard let date = metric.resetsAt else { return metric.resetDescription }
    guard date > now else { return L10n.text("monitor.waitingReset", "到期，等待更新") }
    return L10n.format("monitor.resetsIn", "%@后重置", duration(date.timeIntervalSince(now)))
  }

  static func duration(_ interval: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .abbreviated
    formatter.maximumUnitCount = 1
    formatter.allowedUnits = interval >= 86_400 ? [.day] : interval >= 3_600 ? [.hour] : [.minute]
    var calendar = Calendar.current
    calendar.locale = L10n.locale
    formatter.calendar = calendar
    let unit: Double = interval >= 86_400 ? 86_400 : interval >= 3_600 ? 3_600 : 60
    return formatter.string(from: max(unit, ceil(interval / unit) * unit)) ?? "—"
  }

  static func fullDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = L10n.locale
    formatter.setLocalizedDateFormatFromTemplate("yMMMdjm")
    return formatter.string(from: date) + " · " + TimeZone.current.identifier
  }

  static func updatedText(_ date: Date?, now: Date = Date()) -> String {
    guard let date else { return L10n.text("status.notUpdated", "尚未更新") }
    if now.timeIntervalSince(date) < 60 { return L10n.text("status.updatedJustNow", "刚刚更新") }
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = L10n.locale
    formatter.unitsStyle = .short
    return L10n.format(
      "monitor.updatedRelative", "%@更新", formatter.localizedString(for: date, relativeTo: now))
  }
}
