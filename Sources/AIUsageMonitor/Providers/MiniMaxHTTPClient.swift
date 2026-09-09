import Foundation

enum MiniMaxHTTPClient {
  typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  static func get(
    url: URL, apiKey: String,
    send: Send = { try await URLSession.shared.data(for: $0) }
  ) async throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 15
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let (data, response) = try await send(request)
    guard let response = response as? HTTPURLResponse else { throw HTTPUsageError.invalidResponse }
    guard !(200...299).contains(response.statusCode) else { return data }

    let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    let base = root?["base_resp"] as? [String: Any]
    let nested = root?["error"] as? [String: Any]
    let code = (base?["status_code"] as? Int) ?? (nested?["code"] as? Int)
    let rawMessage =
      (base?["status_msg"] as? String) ?? (nested?["message"] as? String)
      ?? (root?["message"] as? String) ?? (root?["msg"] as? String) ?? (root?["error"] as? String)
    let message = rawMessage.map { value in
      DiagnosticSanitizer.text(
        apiKey.isEmpty ? value : value.replacingOccurrences(of: apiKey, with: "<redacted>"))
    }

    // Preserve terminal account/plan errors; do not mistake them for an unsupported regional route.
    if let code, [1004, 2049, 1008, 1028, 1030, 2056, 2061].contains(code) {
      throw MiniMaxAPIError.service(code: code, message: message)
    }
    let detail = code.map { "MiniMax \($0): " + (message ?? "") } ?? message
    throw HTTPUsageError.server(status: response.statusCode, message: detail)
  }
}
