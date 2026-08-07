import XCTest

@testable import AIUsageMonitor

final class UsageHistoryStoreTests: XCTestCase {
  func testRecordsOnlySuccessfulRefreshesAndNormalizesPercentages() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let connected = state(
      status: .connected,
      value: .used(25, of: 100, unit: "requests"),
      updatedAt: now
    )

    let points = UsageHistoryStore.record(connected, in: [], now: now)

    XCTAssertEqual(points.count, 1)
    XCTAssertEqual(points.first?.scale, .percent)
    XCTAssertEqual(points.first?.value, 75)

    let failed = state(status: .error, value: .availablePercent(5), updatedAt: now)
    XCTAssertEqual(UsageHistoryStore.record(failed, in: points, now: now), points)
  }

  func testDeduplicatesUnchangedSamplesAndReplacesRapidChanges() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let initial = UsageHistoryStore.record(
      state(status: .connected, value: .availablePercent(80), updatedAt: start),
      in: [],
      now: start
    )
    let unchangedDate = start.addingTimeInterval(5 * 60)
    let unchanged = UsageHistoryStore.record(
      state(status: .connected, value: .availablePercent(80), updatedAt: unchangedDate),
      in: initial,
      now: unchangedDate
    )
    XCTAssertEqual(unchanged, initial)

    let changedDate = start.addingTimeInterval(30)
    let changed = UsageHistoryStore.record(
      state(status: .connected, value: .availablePercent(74), updatedAt: changedDate),
      in: initial,
      now: changedDate
    )
    XCTAssertEqual(changed.count, 1)
    XCTAssertEqual(changed.first?.value, 74)
    XCTAssertEqual(changed.first?.recordedAt, changedDate)
  }

  func testKeepsChangedSamplesAndPrunesPointsOlderThanThirtyDays() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let expired = point(
      value: 90,
      date: now.addingTimeInterval(-UsageHistoryStore.retentionInterval - 1)
    )
    let recent = point(value: 80, date: now.addingTimeInterval(-60 * 60))
    let newState = state(
      status: .connected,
      value: .availablePercent(70),
      updatedAt: now
    )

    let result = UsageHistoryStore.record(
      newState,
      in: [expired, recent],
      now: now
    )

    XCTAssertEqual(result.map(\.value), [80, 70])
  }

  private func state(
    status: ProviderConnectionStatus,
    value: UsageValue,
    updatedAt: Date
  ) -> ProviderUsageState {
    ProviderUsageState(
      id: .codex,
      name: "Codex",
      symbolName: "c.circle.fill",
      status: status,
      summary: value,
      metrics: [
        UsageMetric(
          id: "codex.5h",
          label: "5 hours",
          value: value,
          resetsAt: nil,
          resetDescription: nil,
          period: .fiveHour
        )
      ],
      updatedAt: updatedAt,
      message: nil
    )
  }

  private func point(value: Double, date: Date) -> UsageHistoryPoint {
    UsageHistoryPoint(
      providerID: .codex,
      metricID: "codex.5h",
      metricLabel: "5 hours",
      recordedAt: date,
      value: value,
      scale: .percent,
      unit: "%"
    )
  }
}
