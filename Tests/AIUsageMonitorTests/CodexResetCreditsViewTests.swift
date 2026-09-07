import AppKit
import SwiftUI
import XCTest

@testable import AIUsageMonitor

final class CodexResetCreditsViewTests: XCTestCase {
  @MainActor
  func testExpansionFitsMenuWidthAndIncreasesHeight() throws {
    let collapsed = try render(credits: sample, expanded: false)
    let expanded = try render(credits: sample, expanded: true)
    XCTAssertEqual(collapsed.width, 636)
    XCTAssertEqual(expanded.width, 636)
    XCTAssertGreaterThan(expanded.height, collapsed.height + 100)
    try save(collapsed, name: "reset-credits-collapsed")
    try save(expanded, name: "reset-credits-expanded")
  }

  @MainActor
  func testUnavailableAndZeroDoNotExpand() throws {
    for credits in [nil, CodexResetCredits(availableCount: 0, credits: [], updatedAt: .now)] {
      let collapsed = try render(credits: credits, expanded: false)
      let expanded = try render(credits: credits, expanded: true)
      XCTAssertEqual(collapsed.height, expanded.height)
    }
  }

  @MainActor
  func testDarkAppearanceAndPartialDetailsRender() throws {
    let partial = CodexResetCredits(
      availableCount: 3,
      credits: [CodexResetCredit(expiresAt: nil)],
      updatedAt: Date(timeIntervalSince1970: 1_788_800_000)
    )
    let image = try render(credits: partial, expanded: true, dark: true)
    XCTAssertEqual(image.width, 636)
    XCTAssertGreaterThan(image.height, 150)
    try save(image, name: "reset-credits-partial-dark")
  }

  @MainActor
  private func render(
    credits: CodexResetCredits?, expanded: Bool, dark: Bool = false
  ) throws -> CGImage {
    _ = NSApplication.shared
    let renderer = ImageRenderer(
      content:
        CodexResetCreditsView(credits: credits, isExpanded: .constant(expanded))
        .frame(width: 318)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 8)
        .background(dark ? Color.black : Color.white)
        .environment(\.colorScheme, dark ? .dark : .light)
    )
    renderer.scale = 2
    return try XCTUnwrap(renderer.cgImage)
  }

  private func save(_ image: CGImage, name: String) throws {
    guard let path = ProcessInfo.processInfo.environment["AI_USAGE_QA_OUTPUT"] else { return }
    let bitmap = NSBitmapImageRep(cgImage: image)
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: path).appendingPathComponent("\(name).png"))
  }

  private var sample: CodexResetCredits {
    CodexResetCredits(
      availableCount: 3,
      credits: [
        CodexResetCredit(expiresAt: Date(timeIntervalSince1970: 1_789_948_935)),
        CodexResetCredit(expiresAt: Date(timeIntervalSince1970: 1_791_079_853)),
        CodexResetCredit(expiresAt: Date(timeIntervalSince1970: 1_791_173_939)),
      ], updatedAt: Date(timeIntervalSince1970: 1_788_800_000))
  }
}
