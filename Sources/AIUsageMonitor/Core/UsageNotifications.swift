import Foundation
import UserNotifications

struct UsageAlert: Equatable {
  let key: String
  let message: String
  var coveredKeys: [String] = []
}

struct UsageAlertEngine {
  var delivered: [String: Date] = [:]
  private var previousValues: [String: Double] = [:]

  mutating func evaluate(
    _ state: ProviderUsageState, preferences: MonitorPreferences, now: Date = Date()
  ) -> [UsageAlert] {
    guard state.status == .connected, preferences.notificationsEnabled else { return [] }
    delivered = delivered.filter { now.timeIntervalSince($0.value) < 90 * 86_400 }
    var alerts: [UsageAlert] = []
    for metric in state.metrics {
      let ruleKey = MonitorPreferences.metricKey(providerID: state.id, metricID: metric.id)
      let base = ruleKey + "|" + (state.accountScope ?? "local")
      let cycle = metric.resetsAt.map { String($0.timeIntervalSince1970) } ?? "open"
      let deliveryBase = base + "|" + cycle
      let rule = preferences.alertRules[ruleKey] ?? UsageAlertRule()
      let value = metric.value.availableFraction.map { $0 * 100 } ?? metric.value.value
      let previous = previousValues[base]
      previousValues[base] = value
      guard rule.enabled || rule.notifyRecovery else { continue }
      let thresholds = metric.value.kind == .balance ? [rule.balanceThreshold] : rule.thresholds
      guard metric.value.kind == .balance || metric.value.availableFraction != nil else { continue }
      if let previous, value > previous {
        // Once a threshold has recovered, it can notify again on a future crossing.
        for threshold in thresholds where value > threshold {
          delivered[deliveryBase + "|low|\(threshold)"] = nil
        }
      }
      if preferences.isQuiet(at: now) { continue }
      if rule.enabled,
        let threshold = thresholds.filter({ $0.isFinite && $0 >= 0 && value <= $0 }).min()
      {
        let key = deliveryBase + "|low|\(threshold)"
        if delivered[key] == nil {
          alerts.append(
            UsageAlert(
              key: key,
              message:
                UsagePresentation.caption(metric, providerID: state.id) + " "
                + metric.value.displayText,
              coveredKeys: thresholds.filter { $0 >= threshold }.map { deliveryBase + "|low|\($0)" }
            ))
        }
      }
      if rule.notifyRecovery, let previous, let highest = thresholds.max(),
        previous <= highest, value > highest
      {
        alerts.append(
          UsageAlert(
            key: base + "|recovery|\(now.timeIntervalSince1970)",
            message:
              L10n.format("monitor.recovered", "%@额度已恢复：%@", metric.label, metric.value.displayText)
          ))
      }
    }
    if state.id == .codex, let resets = state.resetCredits,
      resets.availableCount > 0, now.timeIntervalSince(resets.updatedAt) < 3_600,
      !preferences.isQuiet(at: now)
    {
      let expiries = Dictionary(grouping: resets.sortedCredits.compactMap(\.expiresAt), by: { $0 })
      for (date, details) in expiries where date > now {
        guard
          let days = preferences.expiryReminderDays.filter({
            $0 > 0 && date.timeIntervalSince(now) <= Double($0) * 86_400
          }).min()
        else { continue }
        let key =
          "codex|\(state.accountScope ?? "local")|expiry|\(date.timeIntervalSince1970)|\(days)"
        if delivered[key] == nil {
          alerts.append(
            UsageAlert(
              key: key,
              message: L10n.format(
                "monitor.expiring", "%d 次重置将在 %@到期", details.count, UsagePresentation.fullDate(date)
              )))
        }
      }
    }
    return alerts
  }

  mutating func markDelivered(_ alerts: [UsageAlert], at now: Date = Date()) {
    for alert in alerts {
      for key in [alert.key] + alert.coveredKeys { delivered[key] = now }
    }
  }
}

@MainActor
final class UsageNotificationService: NSObject, UNUserNotificationCenterDelegate {
  private let center = UNUserNotificationCenter.current()
  var onOpen: (() -> Void)?
  var onSnooze: (() -> Void)?

  override init() {
    super.init()
    center.delegate = self
    let open = UNNotificationAction(
      identifier: "open", title: L10n.text("monitor.viewUsage", "查看额度"), options: .foreground)
    let snooze = UNNotificationAction(
      identifier: "snooze", title: L10n.text("monitor.snooze", "1小时后提醒"), options: [])
    center.setNotificationCategories([
      UNNotificationCategory(identifier: "usage", actions: [open, snooze], intentIdentifiers: [])
    ])
  }

  func requestPermission() async throws -> Bool {
    try await center.requestAuthorization(options: [.alert, .sound])
  }

  func post(provider: ProviderID, alerts: [UsageAlert]) async throws {
    guard !alerts.isEmpty else { return }
    let settings = await center.notificationSettings()
    guard settings.authorizationStatus == .authorized else {
      throw NotificationPermissionError.denied
    }
    let content = UNMutableNotificationContent()
    content.title =
      ProviderCatalog.metadata(for: provider).name + " · " + L10n.text("monitor.usageAlert", "用量提醒")
    content.body = alerts.map(\.message).joined(separator: "\n")
    content.categoryIdentifier = "usage"
    content.threadIdentifier = provider.rawValue
    content.sound = .default
    try await center.add(
      UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    Task { @MainActor in
      if response.actionIdentifier == "snooze" {
        self.onSnooze?()
      } else if response.actionIdentifier != UNNotificationDismissActionIdentifier {
        self.onOpen?()
      }
      completionHandler()
    }
  }
}

enum NotificationPermissionError: LocalizedError {
  case denied
  var errorDescription: String? {
    L10n.text("monitor.notificationsDenied", "通知未获授权，请在系统设置中允许 AI Usage 发送通知。")
  }
}
