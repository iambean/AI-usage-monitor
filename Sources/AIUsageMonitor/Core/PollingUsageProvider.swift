import Foundation

actor PollingUsageProvider: UsageProvider {
  nonisolated let metadata: ProviderMetadata

  private let refreshInterval: TimeInterval
  private let fetch: @Sendable () async throws -> ProviderUsageState
  private var continuation: AsyncStream<ProviderUsageState>.Continuation?
  private var currentState: ProviderUsageState?
  private var pollingTask: Task<Void, Never>?
  private var lastAttemptAt: Date?
  private var isRefreshing = false
  private var consecutiveFailures = 0

  init(
    metadata: ProviderMetadata,
    refreshInterval: TimeInterval = 600,
    fetch: @escaping @Sendable () async throws -> ProviderUsageState
  ) {
    self.metadata = metadata
    self.refreshInterval = refreshInterval
    self.fetch = fetch
  }

  func updates() -> AsyncStream<ProviderUsageState> {
    AsyncStream { continuation in
      self.continuation = continuation
      if let currentState {
        continuation.yield(currentState)
      }
    }
  }

  func start() async {
    guard pollingTask == nil else { return }
    _ = await performRefresh(bypassingManualThrottle: true)
    pollingTask = Task { [weak self] in
      await self?.pollForever()
    }
  }

  func refresh() async {
    _ = await performRefresh(bypassingManualThrottle: false)
  }

  func stop() async {
    pollingTask?.cancel()
    pollingTask = nil
    continuation?.finish()
    continuation = nil
  }

  private func pollForever() async {
    while !Task.isCancelled {
      let delay = nextRefreshDelay
      do {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      _ = await performRefresh(bypassingManualThrottle: true)
    }
  }

  @discardableResult
  private func performRefresh(bypassingManualThrottle: Bool) async -> Bool {
    guard !isRefreshing else { return false }
    let now = Date()
    if !bypassingManualThrottle,
      let lastAttemptAt,
      now.timeIntervalSince(lastAttemptAt) < 30
    {
      return false
    }

    isRefreshing = true
    lastAttemptAt = now
    defer { isRefreshing = false }

    do {
      let state = try await fetch()
      currentState = state
      consecutiveFailures = 0
      continuation?.yield(state)
      return true
    } catch {
      consecutiveFailures += 1
      var state = currentState ?? .loading(metadata.id)
      state.status = .error
      state.message = error.localizedDescription
      currentState = state
      continuation?.yield(state)
      return false
    }
  }

  private var nextRefreshDelay: TimeInterval {
    guard consecutiveFailures > 0 else { return refreshInterval }
    let backoff: [TimeInterval] = [60, 120, 300, 900, 1_800]
    return backoff[min(consecutiveFailures - 1, backoff.count - 1)]
  }
}
