import Foundation

actor CodexUsageProvider: UsageProvider {
  nonisolated let metadata = ProviderMetadata(
    id: .codex,
    name: "Codex",
    symbolName: "c.circle.fill",
    detail: L10n.text("provider.codex.detail", "自动读取 Codex CLI"),
    availability: .available,
    configurationKind: .automatic,
    supportTier: .compatible
  )

  private let client: CodexAppServerClient
  private var continuation: AsyncStream<ProviderUsageState>.Continuation?
  private var currentState: ProviderUsageState?
  private var pollingTask: Task<Void, Never>?
  private var notificationTask: Task<Void, Never>?
  private var isStarted = false
  private var refreshRole = ProviderRefreshRole.primary
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
    guard !isStarted else { return }
    isStarted = true

    let notifications = await client.notifications()
    notificationTask = Task { [weak self] in
      for await notification in notifications {
        guard !Task.isCancelled else { return }
        await self?.handle(notification)
      }
    }

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
    notificationTask?.cancel()
    pollingTask = nil
    notificationTask = nil
    continuation?.finish()
    continuation = nil
    await client.stop()
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
      let result = try await client.readRateLimits()
      let state = try CodexUsageParser.parse(result: result)
      currentState = state
      consecutiveFailures = 0
      continuation?.yield(state)
      return true
    } catch {
      consecutiveFailures += 1
      let state = (currentState ?? .loading(.codex)).failed(
        message: error.localizedDescription,
        recoverySuggestion: ProviderRecoverySuggestion.text(
          for: error,
          providerID: .codex
        )
      )
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

  private var nextRefreshDelay: TimeInterval? {
    ProviderRefreshPolicy.failureDelay(
      baseInterval: 300,
      role: refreshRole,
      consecutiveFailures: consecutiveFailures
    )
  }
}
