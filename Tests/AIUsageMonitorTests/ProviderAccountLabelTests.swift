import AppKit
import SQLite3
import SwiftUI
import XCTest

@testable import AIUsageMonitor

final class ProviderAccountLabelTests: XCTestCase {
  func testKimiUsesFullEmailUsernameOrNicknameAndRejectsErrorPayloads() {
    XCTAssertEqual(
      ProviderAccountLabel.kimi(
        Data(#"{"user_id":"u1","email":"person@example.com","nickname":"Person"}"#.utf8)),
      "person@example.com")
    XCTAssertEqual(
      ProviderAccountLabel.kimi(Data(#"{"user_id":"u1","username":"complete-user-name"}"#.utf8)),
      "complete-user-name")
    XCTAssertEqual(
      ProviderAccountLabel.kimi(Data(#"{"user_id":"u1","email":" ","nickname":"完整昵称"}"#.utf8)),
      "完整昵称")
    XCTAssertNil(ProviderAccountLabel.kimi(Data(#"{"error":"denied","nickname":"Error"}"#.utf8)))
    XCTAssertNil(ProviderAccountLabel.kimi(Data(#"{"user_id":"u1"}"#.utf8)))
  }

  func testQoderOnlyLabelsTheRequestedMember() {
    let data = Data(#"{"id":"member-1","name":"Complete Name","email":"member@example.com"}"#.utf8)
    XCTAssertEqual(ProviderAccountLabel.qoder(data, memberID: "member-1"), "member@example.com")
    XCTAssertNil(ProviderAccountLabel.qoder(data, memberID: "member-2"))
    XCTAssertEqual(
      ProviderAccountLabel.qoder(
        Data(#"{"id":"member-1","name":"Complete Name"}"#.utf8), memberID: "member-1"),
      "Complete Name")
  }

  func testClaudeReadsOnlyTheConfiguredOAuthAccount() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    let file = home.appendingPathComponent(".claude.json")
    try Data(
      #"{"oauthAccount":{"emailAddress":"claude@example.com","displayName":"Full Name"},"userID":"not-a-username"}"#
        .utf8
    ).write(to: file)
    XCTAssertEqual(ProviderAccountLabel.claude(homeDirectory: home), "claude@example.com")
    try Data(#"{"userID":"not-a-username"}"#.utf8).write(to: file)
    XCTAssertNil(ProviderAccountLabel.claude(homeDirectory: home))
  }

  func testCursorEmailReadIsReadOnlyAndDoesNotUseTokens() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let file = home.appendingPathComponent(
      "Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    var database: OpaquePointer?
    XCTAssertEqual(sqlite3_open(file.path, &database), SQLITE_OK)
    XCTAssertEqual(
      sqlite3_exec(
        database,
        "CREATE TABLE ItemTable (key TEXT, value TEXT); INSERT INTO ItemTable VALUES ('cursorAuth/accessToken','not-an-account'), ('cursorAuth/cachedEmail','cursor@example.com');",
        nil, nil, nil), SQLITE_OK)
    sqlite3_close(database)
    let before = try Data(contentsOf: file)
    XCTAssertEqual(ProviderAccountLabel.cursorPersonal(homeDirectory: home), "cursor@example.com")
    XCTAssertEqual(try Data(contentsOf: file), before)
    XCTAssertEqual(sqlite3_open(file.path, &database), SQLITE_OK)
    XCTAssertEqual(
      sqlite3_exec(
        database, "DELETE FROM ItemTable WHERE key = 'cursorAuth/accessToken'", nil, nil, nil),
      SQLITE_OK)
    sqlite3_close(database)
    XCTAssertNil(ProviderAccountLabel.cursorPersonal(homeDirectory: home))
    let absent = home.appendingPathComponent("missing")
    XCTAssertNil(ProviderAccountLabel.cursorPersonal(homeDirectory: absent))
    XCTAssertFalse(FileManager.default.fileExists(atPath: absent.path))
  }

  func testOptionalProfileFailureDoesNotThrow() async {
    let url = URL(string: "https://example.com/me")!
    let result = await ProviderAccountLabel.fetch(url: url, bearerToken: "test-token") { request in
      XCTAssertEqual(request.timeoutInterval, 3)
      XCTAssertEqual(request.httpMethod, "GET")
      return (
        Data(), HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
      )
    }
    XCTAssertNil(result)
  }

  @MainActor
  func testLongAccountLabelsWrapInsteadOfBeingTruncated() throws {
    _ = NSApplication.shared
    func render(_ label: String) throws -> CGImage {
      let state = ProviderUsageState(
        id: .codex, name: "Codex", symbolName: "c.circle", status: .connected,
        summary: .availablePercent(100),
        metrics: [
          UsageMetric(
            id: "codex.primary", label: "周", value: .availablePercent(100), resetsAt: nil,
            resetDescription: nil)
        ],
        updatedAt: .now, message: nil, accountLabel: label)
      let renderer = ImageRenderer(
        content: ProviderUsageRow(state: state)
          .frame(width: 318).fixedSize(horizontal: false, vertical: true))
      return try XCTUnwrap(renderer.cgImage)
    }
    let short = try render("user@example.com · Pro")
    let long = try render(String(repeating: "long.account.name.", count: 5) + "@example.com · Pro")
    XCTAssertEqual(short.width, long.width)
    XCTAssertGreaterThan(
      long.height, short.height, "The account row must grow to show the full name")
  }
}
