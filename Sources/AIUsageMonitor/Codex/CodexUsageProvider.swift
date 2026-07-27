import Foundation

actor CodexUsageProvider: UsageProvider {
  nonisolated let metadata = ProviderMetadata(
    id: .codex,
    name: "Codex",
    symbolName: "c.circle.fill",
    detail: "自动读取 Codex CLI",
    availability: .available,
    configurationKind: .automatic
  )

  private let client: CodexAppServerClient
  private var continuation: AsyncStream<ProviderUsageState>.Continuation?
  private var currentState: ProviderUsageState?
  private var pollingTask: Task<Void, Never>?
  private var notificationTask: Task<Void, Never>?
  private var lastAttemptAt: Date?
  private var isRefreshing = false
  private var consecutiveFailures = 0

  init(executablePath: String) {
    client = CodexAppServerClient(executablePath: executablePath)
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

    let notifications = await client.notifications()
    notificationTask = Task { [weak self] in
      for await notification in notifications {
        guard !Task.isCancelled else { return }
        await self?.handle(notification)
      }
    }

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
    notificationTask?.cancel()
    pollingTask = nil
    notificationTask = nil
    continuation?.finish()
    continuation = nil
    await client.stop()
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
      let result = try await client.readRateLimits()
      let state = try CodexUsageParser.parse(result: result)
      currentState = state
      consecutiveFailures = 0
      continuation?.yield(state)
      return true
    } catch {
      consecutiveFailures += 1
      var state = currentState ?? .loading(.codex)
      state.status = .error
      state.message = error.localizedDescription
      currentState = state
      continuation?.yield(state)
      return false
    }
  }

  private func handle(_ notification: CodexNotification) {
    guard notification.method == "account/rateLimits/updated",
      let state = CodexUsageParser.parseNotification(
        params: notification.params,
        merging: currentState
      )
    else {
      return
    }

    currentState = state
    consecutiveFailures = 0
    continuation?.yield(state)
  }

  private var nextRefreshDelay: TimeInterval {
    guard consecutiveFailures > 0 else { return 300 }
    let backoff: [TimeInterval] = [60, 120, 300, 900, 1_800]
    return backoff[min(consecutiveFailures - 1, backoff.count - 1)]
  }
}
