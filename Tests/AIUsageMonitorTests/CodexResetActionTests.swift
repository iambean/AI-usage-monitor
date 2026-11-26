import AppKit
import SwiftUI
import XCTest

@testable import AIUsageMonitor

@MainActor
final class CodexResetActionTests: XCTestCase {
  // These tests only use a counter callback and fixed outcomes. They never construct
  // a Codex client/provider or invoke AppModel.consumeCodexReset().
  func testOpeningAndCancellingConfirmationNeverUsesAReset() {
    var requested = false
    var calls = 0
    let view = action(binding: Binding(get: { requested }, set: { requested = $0 })) { calls += 1 }
    view.confirm()
    XCTAssertEqual(calls, 0)
    view.requestConfirmation()
    XCTAssertTrue(requested)
    XCTAssertEqual(calls, 0)
    view.cancel()
    view.confirm()
    XCTAssertFalse(requested)
    XCTAssertEqual(calls, 0)
  }

  func testExplicitConfirmationInvokesOnlyTheMockOnce() {
    var requested = false
    var calls = 0
    let view = action(binding: Binding(get: { requested }, set: { requested = $0 })) { calls += 1 }
    view.requestConfirmation()
    view.confirm()
    view.confirm()
    XCTAssertFalse(requested)
    XCTAssertEqual(calls, 1)
  }

  func testLosingEligibilityOrAnInFlightRequestPreventsConfirmation() {
    for running in [false, true] {
      var requested = true
      var calls = 0
      var view = action(binding: Binding(get: { requested }, set: { requested = $0 })) {
        calls += 1
      }
      view.canReset = running
      view.isInProgress = running
      view.confirm()
      XCTAssertEqual(calls, 0)
      view.cancel()
      view.requestConfirmation()
      XCTAssertFalse(requested)
    }
  }

  func testSimulatedOutcomesDistinguishSuccessFromNoConsumptionAndUncertainty() {
    XCTAssertEqual(CodexResetFeedback(outcome: "reset"), .success)
    XCTAssertEqual(CodexResetFeedback(outcome: "alreadyRedeemed"), .alreadyRedeemed)
    XCTAssertEqual(CodexResetFeedback(outcome: "resetRefreshPending"), .pendingRefresh)
    XCTAssertEqual(CodexResetFeedback(outcome: "nothingToReset"), .nothingToReset)
    XCTAssertEqual(CodexResetFeedback(outcome: "noCredit"), .noCredit)
    XCTAssertEqual(CodexResetFeedback(outcome: "unexpected"), .uncertain())
    XCTAssertTrue(
      CodexResetFeedback.uncertain("Simulated timeout").message.contains("Simulated timeout"))
    XCTAssertNotEqual(
      CodexResetFeedback.alreadyRedeemed.message, CodexResetFeedback.success.message)
  }

  func testConfirmationAndResultsFitTheMenuWidth() throws {
    var view = action(binding: .constant(true)) { XCTFail("Rendering must never use a reset") }
    let confirmation = try render(view, name: "reset-confirmation")
    XCTAssertGreaterThan(confirmation.height, 150)
    view.canReset = false
    for (name, feedback) in [
      ("success", CodexResetFeedback.success), ("already-redeemed", .alreadyRedeemed),
      ("pending-refresh", .pendingRefresh), ("nothing-to-reset", .nothingToReset),
      ("no-credit", .noCredit), ("uncertain", .uncertain("Simulated timeout")),
    ] {
      view.feedback = feedback
      let result = try render(view, name: "reset-" + name)
      XCTAssertGreaterThan(result.height, 90, "Feedback must remain visible with no credits left")
    }
    _ = try render(view, name: "reset-uncertain-dark", dark: true)
    view.isInProgress = true
    let progress = try render(view, name: "reset-progress")
    XCTAssertLessThan(progress.height, confirmation.height)
  }

  func testFeedbackRemainsVisibleWhenProviderCannotShowUsage() throws {
    let state = ProviderUsageState.loading(.codex)
    let without = ProviderUsageRow(state: state)
    let with = ProviderUsageRow(state: state, resetFeedback: .pendingRefresh)
    let before = try render(without, name: "reset-provider-loading")
    let after = try render(with, name: "reset-provider-feedback")
    XCTAssertGreaterThan(after.height, before.height + 80)
  }

  private func action(binding: Binding<Bool>, onReset: @escaping () -> Void) -> CodexResetActionView
  {
    CodexResetActionView(
      canReset: true, isInProgress: false, feedback: nil,
      confirmationRequested: binding, onReset: onReset, onDismissFeedback: {})
  }

  private func render<V: View>(_ content: V, name: String, dark: Bool = false) throws -> CGImage {
    _ = NSApplication.shared
    let renderer = ImageRenderer(
      content:
        content
        .frame(width: 318).fixedSize(horizontal: false, vertical: true)
        .padding(12).background(dark ? Color.black : Color.white)
        .environment(\.colorScheme, dark ? .dark : .light))
    renderer.scale = 2
    let image = try XCTUnwrap(renderer.cgImage)
    XCTAssertEqual(image.width, 684)
    if let path = ProcessInfo.processInfo.environment["AI_USAGE_QA_OUTPUT"] {
      let png = try XCTUnwrap(
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
      try png.write(to: URL(fileURLWithPath: path).appendingPathComponent(name + ".png"))
    }
    return image
  }
}
