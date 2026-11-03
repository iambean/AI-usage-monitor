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
  private var accountGeneration = 0
  private var accountRefreshPending = false
  private var lastAuthenticationRecoveryAt: Date?

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
    accountGeneration += 1
    accountRefreshPending = false
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
    guard isStarted, !isRefreshing else { return false }

    let now = Date()
    if !bypassingManualThrottle,
      let lastAttemptAt,
      now.timeIntervalSince(lastAttemptAt) < 30
    {
      return false
    }

    isRefreshing = true
    lastAttemptAt = now
    let generation = accountGeneration
    defer {
      isRefreshing = false
      if accountRefreshPending {
        accountRefreshPending = false
        Task { [weak self] in _ = await self?.performRefresh(bypassingManualThrottle: true) }
      }
    }

    do {
      let state = try await readUsageWithAuthenticationRecovery()
      guard generation == accountGeneration else { return false }
      currentState = state
      consecutiveFailures = 0
      continuation?.yield(state)
      return true
    } catch {
      guard generation == accountGeneration else { return false }
      consecutiveFailures += 1
      let state = (currentState ?? .loading(.codex)).handlingFailure(error)
      currentState = state
      continuation?.yield(state)
      return false
    }
  }

  private func readUsageWithAuthenticationRecovery() async throws -> ProviderUsageState {
    do {
      return try await readUsage()
    } catch let error as CodexClientError where error.isAuthenticationFailure {
      // A refresh can emit account/updated and queue another read. Do not let
      // repeated auth failures turn that notification into a refresh loop.
      let now = Date()
      if let lastAuthenticationRecoveryAt,
        now.timeIntervalSince(lastAuthenticationRecoveryAt) < 30
      {
        throw error
      }
      lastAuthenticationRecoveryAt = now
      // Other Codex clients can rotate shared credentials while our App Server
      // still holds the old tokens. Reload before asking Codex to refresh them.
      await client.stop()
      guard isStarted else { throw CancellationError() }
      _ = try await client.readAccount(refreshToken: true)
      guard isStarted else { throw CancellationError() }
      // One retry only. Re-read identity as well so a new plan/account is not
      // paired with the label or history scope from the expired session.
      return try await readUsage()
    }
  }

  private func readUsage() async throws -> ProviderUsageState {
    let account = CodexAccountIdentity.parse(try await client.readAccount())
    if let oldScope = currentState?.accountScope, oldScope != account?.scope {
      currentState = .loading(.codex)
      continuation?.yield(currentState!)
    }
    let result = try await client.readRateLimits()
    var state = try CodexUsageParser.parse(result: result)
    state.accountLabel = account?.label
    state.accountScope = account?.scope
    return state
  }

  func consumeReset(idempotencyKey: String) async throws -> String {
    let account = CodexAccountIdentity.parse(try await client.readAccount())
    guard account?.scope == currentState?.accountScope, currentState?.status == .connected else {
      _ = await performRefresh(bypassingManualThrottle: true)
      throw CodexClientError.rpc(L10n.text("monitor.accountChanged", "账户已变化，请确认最新额度后再操作。"))
    }
    let outcome = try await client.consumeReset(idempotencyKey: idempotencyKey)
    let refreshed = await performRefresh(bypassingManualThrottle: true)
    if !refreshed && ["reset", "alreadyRedeemed"].contains(outcome) {
      return "resetRefreshPending"
    }
    return outcome
  }

  private func handle(_ notification: CodexNotification) {
    if notification.method == "account/updated" {
      accountGeneration += 1
      accountRefreshPending = isRefreshing
      currentState = .loading(.codex)
      continuation?.yield(currentState!)
      if !isRefreshing {
        Task { [weak self] in
          _ = await self?.performRefresh(bypassingManualThrottle: true)
        }
      }
      return
    }
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
