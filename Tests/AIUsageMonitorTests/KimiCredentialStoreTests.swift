import Foundation
import XCTest

@testable import AIUsageMonitor

final class KimiCredentialStoreTests: XCTestCase {
  func testRefreshesExpiredCredentialsAndPersistsRotatedTokens() async throws {
    let homeDirectory = try makeHomeDirectory()
    defer { try? FileManager.default.removeItem(at: homeDirectory) }

    try KimiCredentialStore.save(
      KimiCredentials(
        accessToken: "expired-access",
        refreshToken: "current-refresh",
        expiresAt: 900,
        scope: "kimi-code",
        tokenType: "Bearer",
        expiresIn: 900
      ),
      homeDirectory: homeDirectory
    )

    let accessToken = try await KimiCredentialStore.accessToken(
      homeDirectory: homeDirectory,
      now: Date(timeIntervalSince1970: 1_000)
    ) { credentials, _, _ in
      XCTAssertEqual(credentials.refreshToken, "current-refresh")
      return KimiCredentials(
        accessToken: "fresh-access",
        refreshToken: "rotated-refresh",
        expiresAt: 1_900,
        scope: "kimi-code",
        tokenType: "Bearer",
        expiresIn: 900
      )
    }

    XCTAssertEqual(accessToken, "fresh-access")
    XCTAssertEqual(
      try KimiCredentialStore.load(homeDirectory: homeDirectory).refreshToken,
      "rotated-refresh"
    )
  }

  func testKeepsFreshCredentialsWithoutRefreshing() async throws {
    let homeDirectory = try makeHomeDirectory()
    defer { try? FileManager.default.removeItem(at: homeDirectory) }

    try KimiCredentialStore.save(
      KimiCredentials(
        accessToken: "fresh-access",
        refreshToken: "refresh",
        expiresAt: 2_000,
        scope: "kimi-code",
        tokenType: "Bearer",
        expiresIn: 900
      ),
      homeDirectory: homeDirectory
    )

    let accessToken = try await KimiCredentialStore.accessToken(
      homeDirectory: homeDirectory,
      now: Date(timeIntervalSince1970: 1_000)
    ) { _, _, _ in
      XCTFail("Fresh credentials must not be refreshed")
      throw KimiOAuthError.invalidResponse
    }

    XCTAssertEqual(accessToken, "fresh-access")
  }

  func testBuildsRefreshRequestAndParsesRotatedCredentials() async throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let credentials = KimiCredentials(
      accessToken: "expired-access",
      refreshToken: "refresh-token",
      expiresAt: 900,
      scope: "kimi-code",
      tokenType: "Bearer",
      expiresIn: 900
    )
    var capturedRequest: URLRequest?

    let refreshed = try await KimiOAuthClient.refresh(
      credentials,
      now: now
    ) { request in
      capturedRequest = request
      let data = Data(
        """
        {
          "access_token": "new-access",
          "refresh_token": "new-refresh",
          "expires_in": 900,
          "scope": "kimi-code",
          "token_type": "Bearer"
        }
        """.utf8
      )
      let response = HTTPURLResponse(
        url: try XCTUnwrap(request.url),
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (data, response)
    }

    let request = try XCTUnwrap(capturedRequest)
    XCTAssertEqual(request.url?.absoluteString, "https://auth.kimi.com/api/oauth/token")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(
      request.value(forHTTPHeaderField: "Content-Type"),
      "application/x-www-form-urlencoded"
    )
    let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
    XCTAssertTrue(body.contains("grant_type=refresh_token"))
    XCTAssertTrue(body.contains("refresh_token=refresh-token"))
    XCTAssertTrue(body.contains("client_id=17e5f671-d194-4dfb-9706-5516cb48c098"))
    XCTAssertEqual(refreshed.accessToken, "new-access")
    XCTAssertEqual(refreshed.refreshToken, "new-refresh")
    XCTAssertEqual(refreshed.expiresAt, 1_900)
  }

  func testCoalescesConcurrentRefreshesAcrossTheCredentialLock() async throws {
    let homeDirectory = try makeHomeDirectory()
    defer { try? FileManager.default.removeItem(at: homeDirectory) }

    try KimiCredentialStore.save(
      KimiCredentials(
        accessToken: "expired-access",
        refreshToken: "current-refresh",
        expiresAt: 900,
        scope: "kimi-code",
        tokenType: "Bearer",
        expiresIn: 900
      ),
      homeDirectory: homeDirectory
    )
    let counter = RefreshCounter()
    let refresh: KimiCredentialStore.Refresh = { _, _, _ in
      await counter.increment()
      try await Task.sleep(nanoseconds: 100_000_000)
      return KimiCredentials(
        accessToken: "fresh-access",
        refreshToken: "rotated-refresh",
        expiresAt: 1_900,
        scope: "kimi-code",
        tokenType: "Bearer",
        expiresIn: 900
      )
    }

    async let first = KimiCredentialStore.accessToken(
      homeDirectory: homeDirectory,
      now: Date(timeIntervalSince1970: 1_000),
      refresh: refresh
    )
    async let second = KimiCredentialStore.accessToken(
      homeDirectory: homeDirectory,
      now: Date(timeIntervalSince1970: 1_000),
      refresh: refresh
    )
    let values = try await (first, second)
    let refreshCount = await counter.value

    XCTAssertEqual(values.0, "fresh-access")
    XCTAssertEqual(values.1, "fresh-access")
    XCTAssertEqual(refreshCount, 1)
  }

  private func makeHomeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }
}

private actor RefreshCounter {
  private(set) var value = 0

  func increment() {
    value += 1
  }
}
