import Foundation

enum DiagnosticSanitizer {
  static func text(
    _ value: String,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> String {
    var result = value.replacingOccurrences(
      of: homeDirectory.path,
      with: "$HOME"
    )
    let patterns = [
      #"(?i)bearer\s+[A-Za-z0-9._~+/=-]+"#,
      #"(?i)(?:api[_-]?key|access[_-]?token|refresh[_-]?token)\s*[:=]\s*["']?[^"'\s,}]+"#,
      #"\bsk-[A-Za-z0-9_-]{8,}\b"#,
      #"\bsk-cp-[A-Za-z0-9_-]{8,}\b"#,
    ]
    for pattern in patterns {
      result = result.replacingOccurrences(
        of: pattern,
        with: "<redacted>",
        options: .regularExpression
      )
    }
    return result
  }
}

enum DiagnosticLog {
  private static let queue = DispatchQueue(label: "com.xinfan.ai-usage-monitor.diagnostics")
  private static let maximumBytes = 256 * 1_024
  private static let retainedBytes = 128 * 1_024

  static var fileURL: URL {
    applicationSupportDirectory
      .appendingPathComponent("diagnostics.log", isDirectory: false)
  }

  static func record(
    _ event: String,
    providerID: ProviderID? = nil,
    fields: [String: String] = [:]
  ) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    var components = [
      timestamp,
      "event=\(safeComponent(event))",
    ]
    if let providerID {
      components.append("provider=\(providerID.rawValue)")
    }
    for key in fields.keys.sorted() {
      guard let value = fields[key] else { continue }
      components.append("\(safeComponent(key))=\(safeComponent(value))")
    }
    let line = DiagnosticSanitizer.text(components.joined(separator: " ")) + "\n"

    queue.async {
      append(line)
    }
  }

  static func flush() {
    queue.sync {}
  }

  private static var applicationSupportDirectory: URL {
    FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    .appendingPathComponent("AI Usage Monitor", isDirectory: true)
  }

  private static func safeComponent(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: " ", with: "_")
  }

  private static func append(_ line: String) {
    let directory = fileURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )

    if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
      let size = attributes[.size] as? NSNumber,
      size.intValue > maximumBytes,
      let data = try? Data(contentsOf: fileURL)
    {
      let suffix = data.suffix(retainedBytes)
      try? Data(suffix).write(to: fileURL, options: .atomic)
    }

    guard let data = line.data(using: .utf8) else { return }
    if !FileManager.default.fileExists(atPath: fileURL.path) {
      FileManager.default.createFile(atPath: fileURL.path, contents: data)
      return
    }
    guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
    defer { try? handle.close() }
    do {
      try handle.seekToEnd()
      try handle.write(contentsOf: data)
    } catch {
      return
    }
  }
}
