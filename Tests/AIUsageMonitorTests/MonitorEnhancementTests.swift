import XCTest

@testable import AIUsageMonitor

final class MonitorEnhancementTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  func testTransientNetworkFailurePreservesLastKnownDataButAuthFailureClearsIt() {
    let state = sample(35)
    let offline = state.handlingFailure(URLError(.notConnectedToInternet))
    XCTAssertEqual(offline.status, .stale)
    XCTAssertEqual(offline.metrics, state.metrics)
    XCTAssertEqual(offline.updatedAt, state.updatedAt)
    XCTAssertEqual(offline.accountScope, "account-a")
    for error in [HTTPUsageError.unauthorized, HTTPUsageError.invalidResponse] {
      let failed = state.handlingFailure(error)
      XCTAssertEqual(failed.status, .error)
      XCTAssertTrue(failed.metrics.isEmpty)
      XCTAssertNil(failed.accountScope)
    }
  }

  func testOnlyKnownTransientFailuresAreTreatedAsStale() {
    XCTAssertTrue(UsageFailurePolicy.isTransient(HTTPUsageError.server(status: 503, message: nil)))
    XCTAssertTrue(UsageFailurePolicy.isTransient(CodexClientError.timeout))
    XCTAssertFalse(
      UsageFailurePolicy.isTransient(CodexClientError.rpc("401 unauthorized connection")))
    XCTAssertFalse(UsageFailurePolicy.isTransient(HTTPUsageError.server(status: 400, message: nil)))
  }

  func testSelectedWindowNeverSilentlyFallsBack() {
    XCTAssertNil(sample(30).selectedMetric("missing"))
    XCTAssertEqual(sample(30).selectedMetric(nil)?.value, .availablePercent(30))
    XCTAssertNil(
      sample(30).failed(message: "error", recoverySuggestion: "retry").selectedMetric(nil))
  }

  func testAllCodexWindowsAreVisibleInGroups() {
    var state = sample(30)
    state.metrics.append(
      UsageMetric(
        id: "codex.secondary", label: "周", value: .availablePercent(40), resetsAt: nil,
        resetDescription: nil, period: .weekly))
    state.metrics.append(
      UsageMetric(
        id: "codex_bengalfox.primary", label: "Spark · 5小时", value: .availablePercent(50),
        resetsAt: nil, resetDescription: nil))
    XCTAssertEqual(state.metricGroups.map { $0.metrics.count }, [2, 1])
    XCTAssertEqual(state.metricGroups.map { $0.name }, ["Default", "Spark"])
  }

  func testExpiredWindowShowsWaitingAndDoesNotChangeQuota() {
    let metric = sample(0, reset: now.addingTimeInterval(-1)).metrics[0]
    XCTAssertEqual(UsagePresentation.resetText(metric, now: now), "到期，等待更新")
    XCTAssertEqual(metric.value, .availablePercent(0))
  }

  func testPreferencesPersistOrderingAndSelectedWindow() throws {
    let name = "MonitorPreferencesTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    var preferences = MonitorPreferences()
    preferences.providerOrder = [.deepseek, .codex, .kimi]
    preferences.selectedMetrics = ["codex": "codex.secondary"]
    preferences.compact = true
    preferences.save(defaults: defaults)
    XCTAssertEqual(MonitorPreferences.load(defaults: defaults), preferences)
    XCTAssertEqual(preferences.ordered([.codex, .kimi, .deepseek]), [.deepseek, .codex, .kimi])
    XCTAssertEqual(preferences.ordered([.codex, .claude]), [.codex, .claude])
  }

  func testQuietHoursCoverMidnightAndEqualHoursMeanAllDay() {
    var preferences = MonitorPreferences()
    preferences.quietHoursEnabled = true
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    func at(_ hour: Int) -> Date {
      calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: hour))!
    }
    XCTAssertTrue(preferences.isQuiet(at: at(23), calendar: calendar))
    XCTAssertTrue(preferences.isQuiet(at: at(7), calendar: calendar))
    XCTAssertFalse(preferences.isQuiet(at: at(8), calendar: calendar))
    preferences.quietStartHour = 9
    preferences.quietEndHour = 17
    XCTAssertTrue(preferences.isQuiet(at: at(12), calendar: calendar))
    XCTAssertFalse(preferences.isQuiet(at: at(20), calendar: calendar))
    preferences.quietStartHour = 17
    XCTAssertTrue(preferences.isQuiet(at: at(1), calendar: calendar))
  }

  func testAlertsAreOptInAndIgnoreStaleData() {
    var engine = UsageAlertEngine()
    XCTAssertTrue(engine.evaluate(sample(5), preferences: MonitorPreferences(), now: now).isEmpty)
    var stale = sample(5)
    stale.status = .stale
    XCTAssertTrue(engine.evaluate(stale, preferences: alertPreferences(), now: now).isEmpty)
  }

  func testThresholdsDeduplicateAndDoNotRepeatLessUrgentAlerts() {
    var engine = UsageAlertEngine()
    let preferences = alertPreferences()
    let first = engine.evaluate(sample(4), preferences: preferences, now: now)
    XCTAssertEqual(first.count, 1)
    engine.markDelivered(first, at: now)
    XCTAssertTrue(engine.evaluate(sample(4), preferences: preferences, now: now).isEmpty)
    XCTAssertTrue(engine.evaluate(sample(6), preferences: preferences, now: now).isEmpty)
    _ = engine.evaluate(sample(25), preferences: preferences, now: now)
    XCTAssertEqual(engine.evaluate(sample(9), preferences: preferences, now: now).count, 1)
  }

  func testLowerThresholdCanAlertAfterHigherThresholdWasDelivered() {
    var engine = UsageAlertEngine()
    let preferences = alertPreferences()
    engine.markDelivered(engine.evaluate(sample(18), preferences: preferences, now: now), at: now)
    XCTAssertEqual(engine.evaluate(sample(9), preferences: preferences, now: now).count, 1)
  }

  func testNewQuotaCycleCanNotifyEvenIfBothSamplesAreLow() {
    var engine = UsageAlertEngine()
    let preferences = alertPreferences()
    engine.markDelivered(
      engine.evaluate(sample(4, reset: now), preferences: preferences, now: now), at: now)
    XCTAssertEqual(
      engine.evaluate(
        sample(4, reset: now.addingTimeInterval(300)), preferences: preferences, now: now
      ).count, 1)
  }

  func testRecoveryCanBeEnabledWithoutLowQuotaNotifications() {
    var engine = UsageAlertEngine()
    var preferences = alertPreferences()
    preferences.alertRules["codex|codex.primary"]?.enabled = false
    preferences.alertRules["codex|codex.primary"]?.notifyRecovery = true
    XCTAssertTrue(engine.evaluate(sample(5), preferences: preferences, now: now).isEmpty)
    XCTAssertEqual(engine.evaluate(sample(80), preferences: preferences, now: now).count, 1)
  }

  func testCurrencyAlertsUseCurrencyThresholdInsteadOfPercent() {
    var engine = UsageAlertEngine()
    var state = sample(80)
    state.metrics = [
      UsageMetric(
        id: "codex.primary", label: "CNY", value: .balance(9, currency: "CNY"), resetsAt: nil,
        resetDescription: nil)
    ]
    XCTAssertEqual(engine.evaluate(state, preferences: alertPreferences(), now: now).count, 1)
  }

  func testRecoveryAlertsRequireAnObservedRecovery() {
    var engine = UsageAlertEngine()
    var preferences = alertPreferences()
    preferences.alertRules["codex|codex.primary"]?.notifyRecovery = true
    XCTAssertTrue(engine.evaluate(sample(90), preferences: preferences, now: now).isEmpty)
    _ = engine.evaluate(sample(5), preferences: preferences, now: now)
    XCTAssertEqual(engine.evaluate(sample(80), preferences: preferences, now: now).count, 1)
    XCTAssertTrue(engine.evaluate(sample(80), preferences: preferences, now: now).isEmpty)
  }

  func testAlertLedgerSeparatesAccounts() {
    var engine = UsageAlertEngine()
    let preferences = alertPreferences()
    engine.markDelivered(engine.evaluate(sample(4), preferences: preferences, now: now), at: now)
    var other = sample(4)
    other.accountScope = "account-b"
    XCTAssertEqual(engine.evaluate(other, preferences: preferences, now: now).count, 1)
  }

  func testQuietPeriodsDoNotMarkUndeliveredAlertsAsDelivered() {
    var engine = UsageAlertEngine()
    var preferences = alertPreferences()
    preferences.snoozedUntil = now.addingTimeInterval(100)
    XCTAssertTrue(engine.evaluate(sample(5), preferences: preferences, now: now).isEmpty)
    XCTAssertEqual(
      engine.evaluate(sample(5), preferences: preferences, now: now.addingTimeInterval(101)).count,
      1)
  }

  func testExpiryAlertsUseKnownFutureExpiriesAndAuthoritativeCount() {
    var engine = UsageAlertEngine()
    var state = sample(100)
    state.resetCredits = CodexResetCredits(
      availableCount: 3,
      credits: [
        CodexResetCredit(expiresAt: now.addingTimeInterval(3_600)),
        CodexResetCredit(expiresAt: nil),
        CodexResetCredit(expiresAt: now.addingTimeInterval(-1)),
      ], updatedAt: now)
    let alerts = engine.evaluate(state, preferences: alertPreferences(), now: now)
    XCTAssertEqual(alerts.count, 1)
    XCTAssertTrue(alerts[0].message.hasPrefix("1 次"))
    engine.markDelivered(alerts, at: now)
    XCTAssertTrue(engine.evaluate(state, preferences: alertPreferences(), now: now).isEmpty)
    state.resetCredits = CodexResetCredits(
      availableCount: 0, credits: state.resetCredits?.credits, updatedAt: now)
    XCTAssertTrue(engine.evaluate(state, preferences: alertPreferences(), now: now).isEmpty)
  }

  func testAccountIdentityMasksEmailAndChangesScopeWithAccountOrPlan() throws {
    func identity(_ email: String, _ plan: String = "pro") throws -> CodexAccountIdentity {
      try XCTUnwrap(
        CodexAccountIdentity.parse(
          .object([
            "account": .object([
              "email": .string(email), "planType": .string(plan),
            ])
          ])))
    }
    let first = try identity("person@example.com")
    XCTAssertFalse(first.label.contains("person@"))
    XCTAssertFalse(first.scope.contains("@"))
    XCTAssertEqual(first, try identity("person@example.com"))
    XCTAssertNotEqual(first.scope, try identity("other@example.com").scope)
    XCTAssertNotEqual(first.scope, try identity("person@example.com", "business").scope)
    XCTAssertNil(CodexAccountIdentity.parse(.object(["account": .null])))
  }

  func testEventsDoNotGuessEveryIncreaseIsAReset() {
    let old = sample(10, reset: now.addingTimeInterval(100))
    var increased = sample(80, reset: now.addingTimeInterval(100))
    XCTAssertEqual(
      UsageHistoryInsights.events(previous: old, current: increased).first?.kind, .increase)
    increased.accountScope = "other"
    XCTAssertTrue(UsageHistoryInsights.events(previous: old, current: increased).isEmpty)
    XCTAssertEqual(
      UsageHistoryInsights.events(
        previous: sample(10, reset: now.addingTimeInterval(-1)),
        current: sample(100, reset: now.addingTimeInterval(300))
      ).first?.kind, .automaticReset)
  }

  func testHistorySegmentsAndHoverDoNotBridgeMissingData() {
    let points = [point(90, -10_000), point(80, -9_000), point(70, -100), point(60, 0)]
    let data = UsageTrendChartData(points: points)
    XCTAssertEqual(data.segments.count, 2)
    XCTAssertTrue(data.isGap(at: now.addingTimeInterval(-4_000)))
    XCTAssertFalse(data.isGap(at: now.addingTimeInterval(-50)))
    XCTAssertTrue(data.values(at: now.addingTimeInterval(-20_000)).isEmpty)
  }

  func testFullQuotaStillRecordsAnObservedNewWindow() {
    let events = UsageHistoryInsights.events(
      previous: sample(100, reset: now.addingTimeInterval(-1)),
      current: sample(100, reset: now.addingTimeInterval(300)))
    XCTAssertEqual(events.map(\.kind), [.automaticReset])
  }

  func testForecastRequiresContinuousRecentConsumptionAndOneAccount() {
    let points = [point(100, -3_600), point(90, -2_400), point(80, -1_200), point(70, 0)]
    XCTAssertEqual(
      UsageHistoryInsights.estimatedExhaustion(points, now: now), now.addingTimeInterval(8_400))
    XCTAssertNil(UsageHistoryInsights.estimatedExhaustion(Array(points.suffix(3)), now: now))
    XCTAssertNil(
      UsageHistoryInsights.estimatedExhaustion(points, now: now.addingTimeInterval(10_000)))
    XCTAssertNil(
      UsageHistoryInsights.estimatedExhaustion(
        [point(100, -3_600), point(80, -2_400), point(100, -1_200), point(90, 0)], now: now))
    XCTAssertNil(
      UsageHistoryInsights.estimatedExhaustion(
        points + [point(60, 1, scope: "other")], now: now.addingTimeInterval(1)))
  }

  func testRetentionAndCSVExportDoNotMergeUnitsOrExecuteFormulas() {
    let points = [point(10, -40 * 86_400), point(9, 0)]
    XCTAssertEqual(UsageHistoryStore.pruned(points, now: now, retentionDays: 90).count, 2)
    XCTAssertEqual(UsageHistoryStore.pruned(points, now: now, retentionDays: 30).count, 1)
    let formula = UsageHistoryPoint(
      providerID: .codex, metricID: "test", metricLabel: "=1+1,\"x\"",
      recordedAt: now, value: 5, scale: .percent, unit: "%")
    let csv = UsageHistoryInsights.csv(points: [formula], events: [])
    XCTAssertTrue(csv.contains("\"'=1+1,\"\"x\"\"\""))
    XCTAssertTrue(csv.contains("time_utc"))
  }

  private func sample(_ percent: Double, reset: Date? = nil) -> ProviderUsageState {
    ProviderUsageState(
      id: .codex, name: "Codex", symbolName: "c.circle", status: .connected,
      summary: .availablePercent(percent),
      metrics: [
        UsageMetric(
          id: "codex.primary", label: "5小时",
          value: .availablePercent(percent), resetsAt: reset, resetDescription: nil,
          period: .fiveHour)
      ],
      updatedAt: now, message: nil, accountScope: "account-a")
  }
  private func alertPreferences() -> MonitorPreferences {
    var preferences = MonitorPreferences()
    preferences.notificationsEnabled = true
    var rule = UsageAlertRule()
    rule.enabled = true
    preferences.alertRules["codex|codex.primary"] = rule
    return preferences
  }
  private func point(_ value: Double, _ offset: Double, scope: String = "account-a")
    -> UsageHistoryPoint
  {
    UsageHistoryPoint(
      providerID: .codex, metricID: "codex.primary", metricLabel: "5小时",
      recordedAt: now.addingTimeInterval(offset), value: value, scale: .percent, unit: "%",
      accountScope: scope)
  }
}
