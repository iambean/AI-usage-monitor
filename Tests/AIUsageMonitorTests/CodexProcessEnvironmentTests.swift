import Foundation
import XCTest

@testable import AIUsageMonitor

final class CodexProcessEnvironmentTests: XCTestCase {
  func testNodeBasedCodexLaunchesWithGUIStylePath() throws {
    let fixtureDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: fixtureDirectory,
      withIntermediateDirectories: true
    )
    defer {
      try? FileManager.default.removeItem(at: fixtureDirectory)
    }

    let nodeURL = fixtureDirectory.appendingPathComponent("node")
    let codexURL = fixtureDirectory.appendingPathComponent("codex")
    try "#!/bin/sh\nexit 0\n".write(to: nodeURL, atomically: true, encoding: .utf8)
    try "#!/usr/bin/env node\n".write(to: codexURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: nodeURL.path
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: codexURL.path
    )

    let process = Process()
    process.executableURL = codexURL
    process.environment = CodexProcessEnvironment.make(
      executablePath: codexURL.path,
      base: [
        "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
      ]
    )
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    try process.run()
    process.waitUntilExit()

    XCTAssertEqual(process.terminationStatus, 0)
  }
}
