import XCTest

@testable import AIUsageMonitor

final class MiniMaxConfigurationTests: XCTestCase {
  func testAuthenticationEnvelopeIsHandledBeforeMissingQuotaFields() {
    let payload = Data(#"{"base_resp":{"status_code":1004,"status_msg":"login fail"}}"#.utf8)
    XCTAssertThrowsError(try MiniMaxUsageParser.parse(payload)) { error in
      XCTAssertFalse(
        error is DecodingError,
        "A regional authentication response must not become a missing-data error")
    }
  }

  func testBusinessErrorWithoutModelRemainsPreservesItsMessage() {
    let payload = Data(
      #"{"base_resp":{"status_code":1008,"status_msg":"insufficient balance"}}"#.utf8)
    XCTAssertThrowsError(try MiniMaxUsageParser.parse(payload)) { error in
      XCTAssertTrue(error.localizedDescription.contains("1008"))
      XCTAssertTrue(error.localizedDescription.contains("insufficient balance"))
    }
  }
  func testAutomaticRegionRetriesBusinessAuthenticationFailureAndCachesChina() async throws {
    let calls = Calls(failure: .service(code: 1004, message: "login fail"))
    let resolver = MiniMaxRegionResolver(preferredRegion: .automatic) { key, region in
      try await calls.fetch(key: key, region: region)
    }
    let state = try await resolver.fetch(apiKey: "test-key")
    XCTAssertEqual(state.status, .connected)
    XCTAssertEqual(state.summary, .availablePercent(80))
    _ = try await resolver.fetch(apiKey: "test-key")
    let visited = await calls.regions
    XCTAssertEqual(visited, [.global, .china, .china])
  }

  func testExplicitRegionDoesNotSilentlySwitchHosts() async {
    let calls = Calls(failure: .service(code: 1004, message: "login fail"))
    let resolver = MiniMaxRegionResolver(preferredRegion: .global) { key, region in
      try await calls.fetch(key: key, region: region)
    }
    do {
      _ = try await resolver.fetch(apiKey: "test-key")
      XCTFail("Expected authentication failure")
    } catch {
      XCTAssertEqual(error as? MiniMaxAPIError, .service(code: 1004, message: "login fail"))
    }
    let visited = await calls.regions
    XCTAssertEqual(visited, [.global])
  }

  func testSubscriptionErrorsDoNotTriggerWrongRegionFallback() async {
    let calls = Calls(failure: .service(code: 1008, message: "insufficient balance"))
    let resolver = MiniMaxRegionResolver(preferredRegion: .automatic) { key, region in
      try await calls.fetch(key: key, region: region)
    }
    do {
      _ = try await resolver.fetch(apiKey: "test-key")
      XCTFail("Expected subscription error")
    } catch {
      XCTAssertEqual(
        error as? MiniMaxAPIError, .service(code: 1008, message: "insufficient balance"))
    }
    let visited = await calls.regions
    XCTAssertEqual(visited, [.global])
  }

  func testBusinessErrorTakesPriorityOverMalformedQuotaPayload() {
    let data = Data(
      #"{"base_resp":{"status_code":1004,"status_msg":"login fail"},"model_remains":"invalid"}"#
        .utf8)
    XCTAssertThrowsError(try MiniMaxUsageParser.parse(data)) { error in
      XCTAssertEqual(error as? MiniMaxAPIError, .service(code: 1004, message: "login fail"))
    }
  }

  func testEmptyOrMalformedSuccessCannotBeSavedAsValidUsage() {
    for raw in [
      #"{"base_resp":{"status_code":0},"model_remains":[]}"#, #"{"base_resp":{"status_code":0}}"#,
    ] {
      XCTAssertThrowsError(try MiniMaxUsageParser.parse(Data(raw.utf8))) { error in
        XCTAssertTrue(error is MiniMaxAPIError)
        XCTAssertFalse(error is DecodingError)
      }
    }
  }

  func testOrdinaryAPIKeyUsesBalanceEndpoint() async throws {
    let state = try await MiniMaxUsageProviderFactory.fetch(apiKey: "sk-api-test", region: .china) {
      url, key in
      XCTAssertEqual(url.absoluteString, "https://api.minimaxi.com/account/query_balance")
      XCTAssertEqual(key, "sk-api-test")
      return Data(
        #"{"available_amount":"98.00","base_resp":{"status_code":0,"status_msg":"success"}}"#.utf8)
    }
    XCTAssertEqual(state.status, .connected)
    XCTAssertEqual(state.summary?.kind, .balance)
    XCTAssertEqual(state.summary?.value, 98)
    XCTAssertEqual(state.summary?.currency, "CNY")
    XCTAssertEqual(state.metrics.first?.value.currency, "CNY")
    XCTAssertNil(state.summary?.availableFraction)
  }

  func testBalanceCurrencyUsesSuccessfulRegionAndHonorsExplicitCurrency() async throws {
    for region in [MiniMaxRegion.china, .global, .automatic] {
      for responseCurrency in [nil, "", "  ", "EUR"] as [String?] {
        let state = try await MiniMaxUsageProviderFactory.fetch(
          apiKey: "sk-api-test", region: region
        ) { _, _ in
          var payload: [String: Any] = [
            "available_amount": "24.62", "base_resp": ["status_code": 0],
          ]
          payload["currency"] = responseCurrency
          return try JSONSerialization.data(withJSONObject: payload)
        }
        let expected = responseCurrency == "EUR" ? "EUR" : (region == .china ? "CNY" : "USD")
        XCTAssertEqual(state.summary?.currency, expected)
        XCTAssertEqual(state.metrics.first?.value.currency, expected)
        XCTAssertTrue(
          state.summary?.displayText.contains(
            expected == "CNY" ? "¥" : expected == "USD" ? "$" : "EUR") == true)
      }
    }
  }

  func testSubscriptionKeyStillUsesQuotaEndpoint() async throws {
    let state = try await MiniMaxUsageProviderFactory.fetch(apiKey: "sk-cp-test", region: .global) {
      url, _ in
      XCTAssertEqual(url.absoluteString, "https://api.minimax.io/v1/token_plan/remains")
      return Data(
        #"{"base_resp":{"status_code":0},"model_remains":[{"model_name":"general","current_interval_remaining_percent":80}]}"#
          .utf8)
    }
    XCTAssertEqual(state.summary, .availablePercent(80))
  }

  func testAutomaticBalanceRouteHandlesRegionalBusinessErrors() async throws {
    let requests = BalanceRequests()
    let state = try await MiniMaxUsageProviderFactory.fetch(
      apiKey: "sk-api-test", region: .automatic
    ) { url, _ in
      await requests.response(url)
    }
    XCTAssertEqual(state.summary?.value, 98)
    XCTAssertEqual(state.summary?.currency, "CNY")
    let urls = await requests.urls
    XCTAssertEqual(
      urls,
      [
        "https://api.minimax.io/account/query_balance",
        "https://api.minimaxi.com/account/query_balance",
      ])
  }

  func testZeroBalanceIsValidButMissingBalanceIsNot() throws {
    XCTAssertEqual(
      try MiniMaxUsageParser.parseBalance(
        Data(#"{"available_amount":0,"base_resp":{"status_code":0}}"#.utf8)
      ).summary?.value, 0)
    XCTAssertThrowsError(
      try MiniMaxUsageParser.parseBalance(Data(#"{"base_resp":{"status_code":0}}"#.utf8)))
    XCTAssertThrowsError(
      try MiniMaxUsageParser.parseBalance(
        Data(#"{"available_amount":false,"base_resp":{"status_code":0}}"#.utf8)))
    XCTAssertThrowsError(
      try MiniMaxUsageParser.parseBalance(
        Data(#"{"available_amount":"NaN","base_resp":{"status_code":0}}"#.utf8)))
  }

  func testAutomaticBalanceRouteContinuesAfterHTTP400() async throws {
    let state = try await MiniMaxUsageProviderFactory.fetch(
      apiKey: "sk-api-test", region: .automatic
    ) { url, _ in
      if url.host == "api.minimax.io" { throw HTTPUsageError.server(status: 400, message: nil) }
      return Data(#"{"available_amount":"98.00","base_resp":{"status_code":0}}"#.utf8)
    }
    XCTAssertEqual(state.status, .connected)
    XCTAssertEqual(state.summary?.value, 98)
  }

  func testHTTP400EnvelopeKeepsMiniMaxErrorDetailsWithoutLeakingKey() async {
    let url = URL(string: "https://api.minimax.io/account/query_balance")!
    do {
      _ = try await MiniMaxHTTPClient.get(url: url, apiKey: "sk-api-private-test") { request in
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let data = Data(
          #"{"base_resp":{"status_code":1000,"status_msg":"biz error: code=2013, params error sk-api-private-test"}}"#
            .utf8)
        return (
          data, HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!
        )
      }
      XCTFail("Expected HTTP 400")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("2013"))
      XCTAssertFalse(error.localizedDescription.contains("sk-api-private-test"))
    }
  }

  func testHTTP400AuthenticationEnvelopeAllowsChinaFallbackThroughTransport() async throws {
    let state = try await MiniMaxUsageProviderFactory.fetch(
      apiKey: "sk-api-test", region: .automatic
    ) { url, key in
      try await MiniMaxHTTPClient.get(url: url, apiKey: key) { request in
        if request.url?.host == "api.minimax.io" {
          return (
            Data(
              #"{"base_resp":{"status_code":1000,"status_msg":"biz error: code=2013, msg=params error"}}"#
                .utf8),
            HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!
          )
        }
        return (
          Data(#"{"available_amount":"98.00","base_resp":{"status_code":0}}"#.utf8),
          HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
      }
    }
    XCTAssertEqual(state.summary?.value, 98)
  }

  func testHTTP400BalanceErrorsRemainTerminal() async {
    let url = URL(string: "https://api.minimax.io/account/query_balance")!
    do {
      _ = try await MiniMaxHTTPClient.get(url: url, apiKey: "sk-api-test") { _ in
        (
          Data(#"{"base_resp":{"status_code":1008,"status_msg":"insufficient balance"}}"#.utf8),
          HTTPURLResponse(url: url, statusCode: 400, httpVersion: nil, headerFields: nil)!
        )
      }
      XCTFail("Expected balance error")
    } catch {
      XCTAssertEqual(
        error as? MiniMaxAPIError, .service(code: 1008, message: "insufficient balance"))
    }
  }

  private actor BalanceRequests {
    var urls: [String] = []
    func response(_ url: URL) -> Data {
      urls.append(url.absoluteString)
      if url.host == "api.minimax.io" {
        return Data(#"{"base_resp":{"status_code":1004,"status_msg":"login fail"}}"#.utf8)
      }
      return Data(#"{"available_amount":"98.00","base_resp":{"status_code":0}}"#.utf8)
    }
  }

  private actor Calls {
    var regions: [MiniMaxRegion] = []
    let failure: MiniMaxAPIError
    init(failure: MiniMaxAPIError) { self.failure = failure }
    func fetch(key: String, region: MiniMaxRegion) throws -> ProviderUsageState {
      regions.append(region)
      if region == .global { throw failure }
      return try MiniMaxUsageParser.parse(
        Data(
          #"{"base_resp":{"status_code":0},"model_remains":[{"model_name":"general","current_interval_remaining_percent":80}]}"#
            .utf8))
    }
  }

}
