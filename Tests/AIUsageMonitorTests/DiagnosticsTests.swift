import XCTest

@testable import AIUsageMonitor

final class DiagnosticsTests: XCTestCase {
  func testSanitizerRemovesHomePathAndCommonCredentialForms() {
    let home = URL(fileURLWithPath: "/Users/example")
    let input = """
      /Users/example/.config token=visible \
      Authorization: Bearer secret.payload.value \
      api_key=sk-cp-abcdefghijklmnop
      """

    let sanitized = DiagnosticSanitizer.text(input, homeDirectory: home)

    XCTAssertFalse(sanitized.contains("/Users/example"))
    XCTAssertFalse(sanitized.contains("secret.payload.value"))
    XCTAssertFalse(sanitized.contains("sk-cp-abcdefghijklmnop"))
    XCTAssertTrue(sanitized.contains("$HOME"))
  }

  func testReportContainsOnlyProviderMetadataAndNotUsageValues() throws {
    let state = ProviderUsageState(
      id: .codex,
      name: "Codex",
      symbolName: "c.circle.fill",
      status: .connected,
      summary: .availablePercent(71),
      metrics: [
        UsageMetric(
          id: "codex.5h",
          label: "5 小时",
          value: .availablePercent(71),
          resetsAt: Date(),
          resetDescription: nil,
          period: .fiveHour
        )
      ],
      updatedAt: Date(),
      message: nil
    )

    let report = DiagnosticsExporter.makeReport(
      states: [state],
      enabledProviderIDs: [.codex],
      lowPowerModeEnabled: false
    )
    let data = try JSONEncoder().encode(report)
    let text = try XCTUnwrap(String(data: data, encoding: .utf8))

    XCTAssertEqual(report.providers.first?.metricCount, 1)
    XCTAssertFalse(text.contains("\"value\":71"))
    XCTAssertFalse(text.contains("5 小时"))
  }

  func testCreatesAReadableDiagnosticsArchive() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let package = root.appendingPathComponent("AI Usage Diagnostics", isDirectory: true)
    let archive = root.appendingPathComponent("diagnostics.zip")
    try FileManager.default.createDirectory(
      at: package,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("{}".utf8).write(to: package.appendingPathComponent("report.json"))

    try DiagnosticsExporter.createArchive(
      packageDirectory: package,
      archiveURL: archive
    )

    let attributes = try FileManager.default.attributesOfItem(atPath: archive.path)
    let size = try XCTUnwrap(attributes[.size] as? NSNumber)
    XCTAssertGreaterThan(size.intValue, 0)
  }
}
