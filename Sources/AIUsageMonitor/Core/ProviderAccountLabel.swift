import Foundation
import SQLite3

// Display-only metadata. It never changes quota identity, account scopes or history keys.
enum ProviderAccountLabel {
  static func firstNonempty(_ values: String?...) -> String? {
    values.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }
  }

  static func kimi(_ data: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      object["user_id"] is String
    else { return nil }
    return firstNonempty(
      object["email"] as? String, object["username"] as? String,
      object["nickname"] as? String)
  }

  static func qoder(_ data: Data, memberID: String) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      object["id"] as? String == memberID
    else { return nil }
    return firstNonempty(object["email"] as? String, object["name"] as? String)
  }

  static func claude(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser)
    -> String?
  {
    guard let data = try? Data(contentsOf: homeDirectory.appendingPathComponent(".claude.json")),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let account = root["oauthAccount"] as? [String: Any]
    else { return nil }
    return firstNonempty(account["emailAddress"] as? String, account["displayName"] as? String)
  }

  static func cursorPersonal(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser)
    -> String?
  {
    let path = homeDirectory.appendingPathComponent(
      "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    ).path
    var database: OpaquePointer?
    guard
      sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK
    else {
      if let database { sqlite3_close(database) }
      return nil
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 50)
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard
      sqlite3_prepare_v2(
        database,
        "SELECT value FROM ItemTable WHERE key = 'cursorAuth/cachedEmail' AND EXISTS (SELECT 1 FROM ItemTable WHERE key = 'cursorAuth/accessToken' AND length(value) > 0) LIMIT 1",
        -1,
        &statement, nil) == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW,
      let raw = sqlite3_column_text(statement, 0)
    else { return nil }
    let value = String(cString: raw)
    let decoded = try? JSONDecoder().decode(String.self, from: Data(value.utf8))
    return firstNonempty(decoded ?? value)
  }

  typealias Send = (URLRequest) async throws -> (Data, URLResponse)

  static func fetch(
    url: URL, bearerToken: String,
    send: Send = { try await URLSession.shared.data(for: $0) }
  ) async -> Data? {
    var request = URLRequest(url: url)
    request.timeoutInterval = 3
    request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    guard let (data, response) = try? await send(request),
      let response = response as? HTTPURLResponse,
      (200...299).contains(response.statusCode)
    else { return nil }
    return data
  }
}
