import Foundation

enum CodexExecutableLocator {
  static func find(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    fileManager: FileManager = .default
  ) -> String? {
    var candidates = pathCandidates(from: environment)
    candidates.append(contentsOf: knownCandidates(homeDirectory: homeDirectory))
    candidates.append(
      contentsOf:
        contentsOfVersionManager(
          homeDirectory.appendingPathComponent(".nvm/versions/node"),
          suffix: "bin/codex",
          fileManager: fileManager
        )
    )
    candidates.append(
      contentsOf:
        contentsOfVersionManager(
          homeDirectory.appendingPathComponent(".fnm/node-versions"),
          suffix: "installation/bin/codex",
          fileManager: fileManager
        )
    )

    var visited = Set<String>()
    return candidates.first { path in
      visited.insert(path).inserted
        && fileManager.isExecutableFile(atPath: path)
    }
  }

  private static func pathCandidates(from environment: [String: String]) -> [String] {
    guard let path = environment["PATH"] else { return [] }
    return
      path
      .split(separator: ":")
      .map { directory in
        URL(fileURLWithPath: String(directory))
          .appendingPathComponent("codex")
          .path
      }
  }

  private static func knownCandidates(homeDirectory: URL) -> [String] {
    [
      homeDirectory.appendingPathComponent(".n/bin/codex").path,
      homeDirectory.appendingPathComponent(".volta/bin/codex").path,
      homeDirectory.appendingPathComponent(".asdf/shims/codex").path,
      homeDirectory.appendingPathComponent(".local/bin/codex").path,
      homeDirectory.appendingPathComponent(".local/share/pnpm/codex").path,
      homeDirectory.appendingPathComponent("Library/pnpm/codex").path,
      homeDirectory.appendingPathComponent(".bun/bin/codex").path,
      "/opt/homebrew/bin/codex",
      "/usr/local/bin/codex",
      "/usr/bin/codex",
    ]
  }

  private static func contentsOfVersionManager(
    _ directory: URL,
    suffix: String,
    fileManager: FileManager
  ) -> [String] {
    guard
      let versions = try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    return
      versions
      .sorted {
        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
          == .orderedDescending
      }
      .map { $0.appendingPathComponent(suffix).path }
  }
}
