import Foundation

enum HTTPUsageError: LocalizedError {
  case invalidResponse
  case unauthorized
  case server(status: Int, message: String?)

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return L10n.text("error.invalidResponse", "服务返回了无法识别的数据")
    case .unauthorized:
      return L10n.text("error.unauthorized", "凭证无效或已过期")
    case .server(let status, let message):
      if let message, !message.isEmpty {
        return L10n.format(
          "error.httpWithMessage",
          "查询失败（HTTP %d）：%@",
          status,
          message
        )
      }
      return L10n.format("error.http", "查询失败（HTTP %d）", status)
    }
  }
}

enum HTTPUsageClient {
  static func get(url: URL, bearerToken: String) async throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 15
    request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw HTTPUsageError.invalidResponse
    }
    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
      throw HTTPUsageError.unauthorized
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      let detail = message?["message"] as? String ?? message?["error"] as? String
      throw HTTPUsageError.server(status: httpResponse.statusCode, message: detail)
    }
    return data
  }

  static func post(
    url: URL,
    basicUsername: String,
    jsonBody: Data
  ) async throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.httpBody = jsonBody
    let credentials = Data("\(basicUsername):".utf8).base64EncodedString()
    request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw HTTPUsageError.invalidResponse
    }
    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
      throw HTTPUsageError.unauthorized
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      let detail = message?["message"] as? String ?? message?["error"] as? String
      throw HTTPUsageError.server(status: httpResponse.statusCode, message: detail)
    }
    return data
  }
}
