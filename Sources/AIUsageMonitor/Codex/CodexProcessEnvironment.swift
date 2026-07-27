import Foundation

enum CodexProcessEnvironment {
  static func make(
    executablePath: String,
    base: [String: String] = ProcessInfo.processInfo.environment
  ) -> [String: String] {
    var environment = base
    let executableDirectory = URL(fileURLWithPath: executablePath)
      .deletingLastPathComponent()
      .path
    let inheritedPath = base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    let pathEntries =
      inheritedPath
      .split(separator: ":")
      .map(String.init)
      .filter { $0 != executableDirectory }

    environment["PATH"] = ([executableDirectory] + pathEntries)
      .joined(separator: ":")
    return environment
  }
}
