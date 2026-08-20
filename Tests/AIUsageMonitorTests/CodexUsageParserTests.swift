import XCTest

@testable import AIUsageMonitor

final class CodexUsageParserTests: XCTestCase {
  func testDefaultLimitDrivesSummaryAndSparkStaysInDetails() throws {
    let result: JSONValue = .object([
      "rateLimitsByLimitId": .object([
        "codex": .object([
          "limitId": .string("codex"),
          "secondary": .object([
            "usedPercent": .number(95),
            "windowDurationMins": .number(10_080),
          ]),
        ]),
        "codex_bengalfox": .object([
          "limitId": .string("codex_bengalfox"),
          "limitName": .string("Spark"),
          "primary": .object([
            "usedPercent": .number(0),
            "windowDurationMins": .number(300),
          ]),
          "secondary": .object([
            "usedPercent": .number(25),
            "windowDurationMins": .number(10_080),
          ]),
        ]),
      ])
    ])

    let state = try CodexUsageParser.parse(result: result)

    XCTAssertEqual(state.summary, .availablePercent(5))
    XCTAssertEqual(state.defaultSummary, .availablePercent(5))
    XCTAssertEqual(state.codexDefaultMetric?.id, "codex.secondary")
    XCTAssertEqual(
      state.codexSparkMetrics.map(\.value),
      [.availablePercent(100), .availablePercent(75)]
    )
  }

  func testDefaultLimitPrefersFiveHourWindowOverWeeklyWindow() throws {
    let result: JSONValue = .object([
      "rateLimitsByLimitId": .object([
        "codex": .object([
          "limitId": .string("codex"),
          "primary": .object([
            "usedPercent": .number(20),
            "windowDurationMins": .number(300),
          ]),
          "secondary": .object([
            "usedPercent": .number(95),
            "windowDurationMins": .number(10_080),
          ]),
        ]),
        "codex_bengalfox": .object([
          "limitId": .string("codex_bengalfox"),
          "limitName": .string("Spark"),
          "primary": .object([
            "usedPercent": .number(0),
            "windowDurationMins": .number(300),
          ]),
        ]),
      ])
    ])

    let state = try CodexUsageParser.parse(result: result)

    XCTAssertEqual(state.summary, .availablePercent(80))
    XCTAssertEqual(state.defaultSummary, .availablePercent(80))
    XCTAssertEqual(state.codexDefaultMetric?.id, "codex.primary")
  }

  func testSparkNeverBecomesSummaryWhenDefaultLimitIsMissing() throws {
    let result: JSONValue = .object([
      "rateLimitsByLimitId": .object([
        "codex_bengalfox": .object([
          "limitId": .string("codex_bengalfox"),
          "limitName": .string("Spark"),
          "primary": .object([
            "usedPercent": .number(0),
            "windowDurationMins": .number(300),
          ]),
        ]),
      ])
    ])

    let state = try CodexUsageParser.parse(result: result)

    XCTAssertNil(state.summary)
    XCTAssertNil(state.defaultSummary)
    XCTAssertNil(state.codexDefaultMetric)
    XCTAssertEqual(state.codexSparkMetrics.map(\.value), [.availablePercent(100)])
  }

  func testUsesFiveHourWindowAsDefaultSummaryWhenWeeklyWindowAlsoExists() throws {
    let result: JSONValue = .object([
      "rateLimits": .object([
        "limitId": .string("codex"),
        "primary": .object([
          "usedPercent": .number(35),
          "windowDurationMins": .number(300),
          "resetsAt": .number(2_000_000_000),
        ]),
        "secondary": .object([
          "usedPercent": .number(62),
          "windowDurationMins": .number(10_080),
          "resetsAt": .number(2_000_100_000),
        ]),
      ])
    ])

    let state = try CodexUsageParser.parse(result: result)

    XCTAssertEqual(state.summary, .availablePercent(65))
    XCTAssertEqual(
      state.metrics,
      [
        UsageMetric(
          id: "codex.primary",
          label: "5 小时",
          value: .availablePercent(65),
          resetsAt: Date(timeIntervalSince1970: 2_000_000_000),
          resetDescription: nil,
          period: .fiveHour
        ),
        UsageMetric(
          id: "codex.secondary",
          label: "周期",
          value: .availablePercent(38),
          resetsAt: Date(timeIntervalSince1970: 2_000_100_000),
          resetDescription: nil,
          period: .weekly
        ),
      ]
    )
  }

  func testUsesWeeklyWindowWhenItIsTheOnlyAvailableWindow() throws {
    let result: JSONValue = .object([
      "rateLimits": .object([
        "limitId": .string("codex"),
        "secondary": .object([
          "usedPercent": .number(31),
          "windowDurationMins": .number(10_080),
          "resetsAt": .number(2_000_100_000),
        ]),
      ])
    ])

    let state = try CodexUsageParser.parse(result: result)

    XCTAssertEqual(state.summary, .availablePercent(69))
  }

  func testClampsUnexpectedUsageValues() throws {
    let result: JSONValue = .object([
      "rateLimits": .object([
        "primary": .object([
          "usedPercent": .number(140),
          "windowDurationMins": .number(300),
        ]),
        "secondary": .object([
          "usedPercent": .number(-20),
          "windowDurationMins": .number(10_080),
        ]),
      ])
    ])

    let state = try CodexUsageParser.parse(result: result)

    XCTAssertEqual(state.metrics.map(\.value.value), [0, 100])
    XCTAssertEqual(state.summary, .availablePercent(0))
  }

  func testSparseNotificationKeepsUnchangedWindow() throws {
    let initial = try CodexUsageParser.parse(
      result: .object([
        "rateLimits": .object([
          "limitId": .string("codex"),
          "primary": .object([
            "usedPercent": .number(35),
            "windowDurationMins": .number(300),
          ]),
          "secondary": .object([
            "usedPercent": .number(62),
            "windowDurationMins": .number(10_080),
          ]),
        ])
      ])
    )

    let updated = CodexUsageParser.parseNotification(
      params: .object([
        "rateLimits": .object([
          "limitId": .string("codex"),
          "primary": .object([
            "usedPercent": .number(40),
            "windowDurationMins": .number(300),
          ]),
        ])
      ]),
      merging: initial
    )

    XCTAssertEqual(updated?.metrics.map(\.value.value), [60, 38])
    XCTAssertEqual(updated?.summary, .availablePercent(60))
  }
}
