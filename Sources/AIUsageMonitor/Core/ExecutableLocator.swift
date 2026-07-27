import Foundation

enum ExecutableLocator {
  static func find(
    name: String,
    knownRelativePaths: [String] = [],
    environment: [String: String] = ProcessInfo.processInfo.environment,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    fileManager: FileManager = .default
  ) -> String? {
    var candidates =
      (environment["PATH"] ?? "")
      .split(separator: ":")
      .map {
        URL(fileURLWithPath: String($0))
          .appendingPathComponent(name)
          .path
      }
    candidates.append(
      contentsOf: knownRelativePaths.map {
        homeDirectory.appendingPathComponent($0).path
      }
    )
    candidates.append(contentsOf: [
      "/opt/homebrew/bin/\(name)",
      "/usr/local/bin/\(name)",
      "/usr/bin/\(name)",
    ])

    var visited = Set<String>()
    return candidates.first {
      visited.insert($0).inserted && fileManager.isExecutableFile(atPath: $0)
    }
  }
}
