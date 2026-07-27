import Foundation
import XCTest

@testable import AIUsageMonitor

final class CodexExecutableLocatorTests: XCTestCase {
  func testFindsCodexFromPath() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    let result = CodexExecutableLocator.find(
      environment: ["PATH": fixture.bin.path],
      homeDirectory: fixture.home
    )

    XCTAssertEqual(result, fixture.codex.path)
  }

  func testFindsCodexInstalledByNWhenGUIPathIsMinimal() throws {
    let fixture = try makeFixture(relativeCodexPath: ".n/bin/codex")
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    let result = CodexExecutableLocator.find(
      environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"],
      homeDirectory: fixture.home
    )

    XCTAssertEqual(result, fixture.codex.path)
  }

  private func makeFixture(
    relativeCodexPath: String = "bin/codex"
  ) throws -> (
    root: URL,
    home: URL,
    bin: URL,
    codex: URL
  ) {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let home = root.appendingPathComponent("home", isDirectory: true)
    let codex = home.appendingPathComponent(relativeCodexPath)
    let bin = codex.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: bin,
      withIntermediateDirectories: true
    )
    try "#!/bin/sh\nexit 0\n".write(
      to: codex,
      atomically: true,
      encoding: .utf8
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: codex.path
    )
    return (root, home, bin, codex)
  }
}
