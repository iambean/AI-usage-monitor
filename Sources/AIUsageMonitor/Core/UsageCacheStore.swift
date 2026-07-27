import Foundation

enum UsageCacheStore {
  private static var cacheURL: URL? {
    guard
      let applicationSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      return nil
    }

    return
      applicationSupport
      .appendingPathComponent("AI Usage Monitor", isDirectory: true)
      .appendingPathComponent("usage-cache.json", isDirectory: false)
  }

  static func load() -> [ProviderUsageState] {
    guard let cacheURL,
      let data = try? Data(contentsOf: cacheURL),
      var states = try? JSONDecoder().decode([ProviderUsageState].self, from: data)
    else {
      return []
    }

    for index in states.indices {
      states[index].status = .stale
      states[index].message = "正在更新"
    }
    return states
  }

  static func save(_ states: [ProviderUsageState]) {
    guard let cacheURL,
      let data = try? JSONEncoder().encode(states)
    else {
      return
    }

    let directory = cacheURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    try? data.write(to: cacheURL, options: .atomic)
  }
}
