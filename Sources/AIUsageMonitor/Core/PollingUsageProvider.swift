import Foundation

actor PollingUsageProvider: UsageProvider {
  nonisolated let metadata: ProviderMetadata

  private let baseRefreshInterval: TimeInterval
  private let fetch: @Sendable () async throws -> ProviderUsageState
  private var continuation: AsyncStream<ProviderUsageState>.Continuation?
  private var currentState: ProviderUsageState?
  private var pollingTask: Task<Void, Never>?
  private var isStarted = false
  private var refreshRole = ProviderRefreshRole.primary
  private var lastAttemptAt: Date?
  private var isRefreshing = false
  private var consecutiveFailures = 0

  init(
    metadata: ProviderMetadata,
    refreshInterval: TimeInterval = 600,
    fetch: @escaping @Sendable () async throws -> ProviderUsageState
  ) {
    self.metadata = metadata
    baseRefreshInterval = refreshInterval
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
    guard !isStarted else { return }
    isStarted = true
    _ = await performRefresh(bypassingManualThrottle: true)
    restartPolling()
  }

  func refresh() async {
    _ = await performRefresh(bypassingManualThrottle: false)
  }

  func setRefreshRole(_ role: ProviderRefreshRole) async {
    guard refreshRole != role else { return }
    refreshRole = role
    if isStarted {
      restartPolling()
    }
  }

  func stop() async {
    isStarted = false
    pollingTask?.cancel()
    pollingTask = nil
    continuation?.finish()
    continuation = nil
  }

  private func pollForever() async {
    while !Task.isCancelled {
      guard let delay = nextRefreshDelay else { return }
      do {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      _ = await performRefresh(bypassingManualThrottle: true)
    }
  }

  private func restartPolling() {
    pollingTask?.cancel()
    pollingTask = nil
    guard nextRefreshDelay != nil else { return }
    pollingTask = Task { [weak self] in
      await self?.pollForever()
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
      let state = (currentState ?? .loading(metadata.id)).failed(
        message: error.localizedDescription,
        recoverySuggestion: ProviderRecoverySuggestion.text(
          for: error,
          providerID: metadata.id
        )
      )
      currentState = state
      continuation?.yield(state)
      return false
    }
  }

  private var nextRefreshDelay: TimeInterval? {
    ProviderRefreshPolicy.failureDelay(
      baseInterval: baseRefreshInterval,
      role: refreshRole,
      consecutiveFailures: consecutiveFailures
    )
  }
}
