import XCTest

@testable import AIUsageMonitor

final class CodexUsageParserTests: XCTestCase {
  func testParsesAvailablePercentAndUsesMostConstrainedWindowAsSummary() throws {
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

    XCTAssertEqual(state.summary, .availablePercent(38))
    XCTAssertEqual(
      state.metrics,
      [
        UsageMetric(
          id: "codex.primary",
          label: "5 小时",
          value: .availablePercent(65),
          resetsAt: Date(timeIntervalSince1970: 2_000_000_000),
          resetDescription: nil
        ),
        UsageMetric(
          id: "codex.secondary",
          label: "周期",
          value: .availablePercent(38),
          resetsAt: Date(timeIntervalSince1970: 2_000_100_000),
          resetDescription: nil
        ),
      ]
    )
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
    XCTAssertEqual(updated?.summary, .availablePercent(38))
  }
}
