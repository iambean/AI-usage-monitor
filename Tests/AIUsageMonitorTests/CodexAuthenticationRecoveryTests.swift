import Foundation
import XCTest

@testable import AIUsageMonitor

final class CodexAuthenticationRecoveryTests: XCTestCase {
  func testExpiredResidentSessionReloadsAndRefreshesBeforeRetryingUsage() async throws {
    let result = try await runProvider(scenario: "expired")
    XCTAssertEqual(result.state.status, .connected)
    XCTAssertEqual(result.state.accountLabel, "fixture@example.com · Pro")
    XCTAssertEqual(result.state.metrics.first?.value.value, 75)
    XCTAssertEqual(result.launches, 2)
    XCTAssertEqual(result.methods.filter { $0 == "refresh" }.count, 1)
    XCTAssertEqual(result.methods.filter { $0 == "account/rateLimits/read" }.count, 2)
  }

  func testPersistentUnauthorizedStopsAfterOneRecoveryAttempt() async throws {
    let result = try await runProvider(scenario: "always_expired")
    XCTAssertEqual(result.state.status, .error)
    XCTAssertTrue(result.state.metrics.isEmpty)
    XCTAssertEqual(result.launches, 2)
    XCTAssertEqual(result.methods.filter { $0 == "refresh" }.count, 1)
    XCTAssertEqual(result.methods.filter { $0 == "account/rateLimits/read" }.count, 2)
    XCTAssertFalse(result.state.message?.contains("backend-api") ?? true)
    XCTAssertTrue(result.state.recoverySuggestion?.contains("codex login") ?? false)
  }

  func testRejectedRefreshDoesNotLoopOrRetryUsage() async throws {
    let result = try await runProvider(scenario: "refresh_rejected")
    XCTAssertEqual(result.state.status, .error)
    XCTAssertEqual(result.launches, 2)
    XCTAssertEqual(result.methods.filter { $0 == "refresh" }.count, 1)
    XCTAssertEqual(result.methods.filter { $0 == "account/rateLimits/read" }.count, 1)
  }

  func testHealthySessionDoesNotRotateTokensOrRestart() async throws {
    let result = try await runProvider(scenario: "healthy")
    XCTAssertEqual(result.state.status, .connected)
    XCTAssertEqual(result.launches, 1)
    XCTAssertFalse(result.methods.contains("refresh"))
  }

  func testAccountUpdateDuringRecoveryPublishesTheNewPlan() async throws {
    let result = try await runProvider(scenario: "notify")
    XCTAssertEqual(result.state.status, .connected)
    XCTAssertEqual(result.state.accountLabel, "fixture@example.com · Pro")
    XCTAssertEqual(result.launches, 2)
    XCTAssertEqual(result.methods.filter { $0 == "refresh" }.count, 1)
  }

  func testAccountUpdateWithPersistentUnauthorizedDoesNotStartARecoveryLoop() async throws {
    let result = try await runProvider(scenario: "notify_always_expired")
    XCTAssertEqual(result.state.status, .error)
    XCTAssertTrue(result.state.metrics.isEmpty)
    XCTAssertEqual(result.launches, 2)
    XCTAssertEqual(result.methods.filter { $0 == "refresh" }.count, 1)
    XCTAssertLessThanOrEqual(result.methods.filter { $0 == "account/rateLimits/read" }.count, 3)
  }

  func testNetworkAndPermissionErrorsDoNotRefreshCredentials() async throws {
    for scenario in ["network", "forbidden"] {
      let result = try await runProvider(scenario: scenario)
      XCTAssertEqual(result.state.status, .error)
      XCTAssertEqual(result.launches, 1)
      XCTAssertFalse(result.methods.contains("refresh"))
      XCTAssertEqual(result.methods.filter { $0 == "account/rateLimits/read" }.count, 1)
    }
  }

  private func runProvider(scenario: String) async throws -> (
    state: ProviderUsageState, launches: Int, methods: [String]
  ) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try scenario.write(to: directory.appendingPathComponent("scenario"), atomically: true, encoding: .utf8)
    let executable = directory.appendingPathComponent("codex-fixture")
    try Self.server.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

    let provider = CodexUsageProvider(executablePath: executable.path)
    let updates = await provider.updates()
    await provider.start()
    var iterator = updates.makeAsyncIterator()
    var state = await iterator.next()
    while state?.status == .loading {
      state = await iterator.next()
    }
    await provider.stop()
    let events = try String(contentsOf: directory.appendingPathComponent("events"))
      .split(separator: "\n").map(String.init)
    XCTAssertFalse(events.contains("account/rateLimitResetCredit/consume"))
    return (try XCTUnwrap(state), events.filter { $0 == "launch" }.count, events)
  }

  // Real provider/client and JSON-RPC pipes; synthetic credentials only, no network.
  private static let server = #"""
    #!/usr/bin/python3
    import json, pathlib, sys
    root = pathlib.Path(__file__).parent
    scenario = (root / 'scenario').read_text()
    def log(event):
        with (root / 'events').open('a') as f:
            f.write(event + '\n')
    log('launch')
    launches = (root / 'events').read_text().splitlines().count('launch')
    refreshed = False
    for line in sys.stdin:
        request = json.loads(line)
        if 'id' not in request:
            continue
        method = request['method']
        log(method)
        result = {}
        error = None
        if method == 'account/read':
            if request.get('params', {}).get('refreshToken'):
                log('refresh')
                refreshed = True
                if scenario == 'refresh_rejected':
                    error = 'Your refresh token has expired. Please log in again.'
                if scenario.startswith('notify'):
                    print(json.dumps({'method': 'account/updated', 'params': {
                        'authMode': 'chatgpt', 'planType': 'pro'}}), flush=True)
            result = {'account': {'type': 'chatgpt', 'email': 'fixture@example.com',
                'planType': 'pro' if refreshed or scenario == 'healthy' else 'plus'}}
        elif method == 'account/rateLimits/read':
            if scenario == 'network':
                error = 'error sending request: connection timed out'
            elif scenario == 'forbidden':
                error = '403 Forbidden'
            elif scenario.endswith('always_expired') or (scenario != 'healthy' and (launches == 1 or not refreshed)):
                error = 'failed to fetch codex rate limits: GET https://chatgpt.com/backend-api/wham/usage failed: 401 Unauthorized; content-type=text/plain; body={"error":{"message":"Provided authentication token is expired.","code":"token_expired"}}'
            result = {'rateLimits': {'planType': 'pro', 'primary': {
                'usedPercent': 25, 'windowDurationMins': 300, 'resetsAt': 1900000000}}}
        elif method != 'initialize':
            error = 'Unexpected method'
        response = {'id': request['id']}
        if error:
            response['error'] = {'code': -32000, 'message': error}
        else:
            response['result'] = result
        print(json.dumps(response), flush=True)
    """#
}
