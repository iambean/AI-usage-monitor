import AppKit
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var providerStates: [ProviderUsageState]
  @Published private(set) var enabledProviderIDs: [ProviderID]
  @Published private(set) var primaryProviderID: ProviderID
  @Published private(set) var launchAtLoginEnabled: Bool
  @Published private(set) var launchAtLoginError: String?
  @Published private(set) var detectedExecutablePaths: [ProviderID: String]
  @Published private(set) var configurationMessages: [ProviderID: String] = [:]
  @Published private(set) var testingProviderID: ProviderID?
  @Published private(set) var lowPowerModeEnabled: Bool
  @Published private(set) var diagnosticsMessage: String?
  @Published private(set) var updateStatus = AppUpdateStatus.idle
  @Published private(set) var credentialAvailability: [ProviderID: Bool] = [:]
  @Published private(set) var cursorAccountMode: CursorAccountMode
  @Published private(set) var usageHistory: [UsageHistoryPoint]
  @Published private(set) var appLanguage: AppLanguage

  @Published private(set) var preferences = MonitorPreferences.load()
  @Published private(set) var refreshingProviders: Set<ProviderID> = []
  @Published private(set) var usageEvents: [UsageHistoryEvent] = UsageEventStore.load()
  @Published private(set) var notificationMessage: String?
  @Published private(set) var historyMessage: String?
  @Published private(set) var resetInProgress = false
  @Published private(set) var resetMessage: String?
  private var maintenanceTask: Task<Void, Never>?
  private var checkedResets: [String: Date] = [:]
  private var historyRevision = 0
  private var alertEngine = UsageAlertEngine()
  private var pendingAlerts: Set<String> = []
  private lazy var notificationService: UsageNotificationService = {
    let service = UsageNotificationService()
    service.onOpen = {
      NotificationCenter.default.post(name: .aiUsageOpenPanel, object: nil)
    }
    service.onSnooze = { [weak self] in
      self?.updatePreferences { $0.snoozedUntil = Date().addingTimeInterval(3_600) }
      self?.alertEngine.delivered.removeAll()
      UserDefaults.standard.removeObject(forKey: "usage-alert-ledger")
    }
    return service
  }()

  var currentVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
      as? String ?? "0.0.0"
  }

  private var providers: [ProviderID: any UsageProvider] = [:]
  private lazy var appUpdater = AppUpdater()
  private let updateChecker = UpdateChecker()
  private let usageHistoryWriter = UsageHistoryWriter()
  private var updateTasks: [ProviderID: Task<Void, Never>] = [:]
  private var startTasks: [ProviderID: Task<Void, Never>] = [:]
  private var connectionGenerations: [ProviderID: UUID] = [:]
  private var powerStateObserver: NSObjectProtocol?
  private var wakeObserver: NSObjectProtocol?
  private let isPreview: Bool
  private var hasStarted = false
  private var isShuttingDown = false

  init(
    previewStates: [ProviderUsageState]? = nil,
    previewHistory: [UsageHistoryPoint] = [],
    previewEvents: [UsageHistoryEvent] = []
  ) {
    if let previewStates {
      isPreview = true
      appLanguage = .simplifiedChinese
      enabledProviderIDs = previewStates.map(\.id)
      primaryProviderID = previewStates.first?.id ?? .codex
      providerStates = previewStates
      launchAtLoginEnabled = false
      detectedExecutablePaths = [:]
      lowPowerModeEnabled = false
      cursorAccountMode = .teams
      usageHistory = previewHistory
      usageEvents = previewEvents
      preferences = MonitorPreferences()
      return
    }
    isPreview = false
    appLanguage = AppLanguageStore.load()
    var enabled = ProviderSettingsStore.enabledProviderIDs()
    let primary = ProviderSettingsStore.primaryProviderID(
      enabledProviderIDs: enabled
    )
    enabled = MonitorPreferences.load().ordered(
      ProviderOrder.withPrimaryFirst(enabled, primary: primary))
    enabledProviderIDs = enabled
    primaryProviderID = primary
    ProviderSettingsStore.setEnabledProviderIDs(enabled)
    ProviderSettingsStore.setPrimaryProviderID(primary)
    let cached = UsageCacheStore.load()
    providerStates = enabled.map { id in
      cached.first(where: { $0.id == id }) ?? .loading(id)
    }
    launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    detectedExecutablePaths = Self.detectExecutables()
    lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    cursorAccountMode = ProviderSettingsStore.cursorAccountMode()
    usageHistory = UsageHistoryStore.load(retentionDays: MonitorPreferences.load().retentionDays)

    powerStateObserver = NotificationCenter.default.addObserver(
      forName: Notification.Name.NSProcessInfoPowerStateDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.updatePowerState()
      }
    }
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        if self?.preferences.refreshAfterWake == true {
          self?.refresh()
        } else {
          self?.refreshPrimary()
        }
      }
    }
    refreshCredentialAvailability()
    if let data = UserDefaults.standard.data(forKey: "usage-alert-ledger"),
      let ledger = try? JSONDecoder().decode([String: Date].self, from: data)
    {
      alertEngine.delivered = ledger
    }
    applyAppearance()
    pruneHistory()
  }

  deinit {
    maintenanceTask?.cancel()
    if let powerStateObserver {
      NotificationCenter.default.removeObserver(powerStateObserver)
    }
    if let wakeObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
    }
    for task in startTasks.values {
      task.cancel()
    }
    for task in updateTasks.values {
      task.cancel()
    }
  }

  var primaryState: ProviderUsageState {
    state(for: primaryProviderID) ?? .loading(primaryProviderID)
  }

  var qoderConfiguration: QoderConfiguration {
    ProviderSettingsStore.qoderConfiguration()
  }

  var miniMaxRegion: MiniMaxRegion {
    ProviderSettingsStore.miniMaxRegion()
  }

  func isProviderEnabled(_ id: ProviderID) -> Bool {
    enabledProviderIDs.contains(id)
  }

  func isPrimaryProvider(_ id: ProviderID) -> Bool {
    primaryProviderID == id
  }

  func setPrimaryProvider(_ id: ProviderID) {
    guard enabledProviderIDs.contains(id), primaryProviderID != id else { return }
    primaryProviderID = id
    ProviderSettingsStore.setPrimaryProviderID(id)
    orderEnabledProviders()
    orderStates()
    ProviderSettingsStore.setEnabledProviderIDs(enabledProviderIDs)
    UsageCacheStore.save(providerStates)
    applyRefreshRoles()
  }

  func hasCredential(_ id: ProviderID) -> Bool {
    switch id {
    case .cursor:
      return cursorAccountMode == .personal
        || (credentialAvailability[id] ?? false)
    case .minimax, .deepseek, .qoder:
      return credentialAvailability[id] ?? false
    default:
      return true
    }
  }

  func state(for id: ProviderID) -> ProviderUsageState? {
    providerStates.first(where: { $0.id == id })
  }

  var trendProviderIDs: [ProviderID] {
    let historicalProviderIDs = Set(usageHistory.map(\.providerID))
    return ProviderCatalog.all.compactMap { metadata in
      enabledProviderIDs.contains(metadata.id) || historicalProviderIDs.contains(metadata.id)
        ? metadata.id
        : nil
    }
  }

  func setCursorAccountMode(_ mode: CursorAccountMode) {
    guard cursorAccountMode != mode else { return }
    cursorAccountMode = mode
    ProviderSettingsStore.setCursorAccountMode(mode)
    configurationMessages[.cursor] = nil

    guard isProviderEnabled(.cursor) else { return }
    if let index = providerStates.firstIndex(where: { $0.id == .cursor }) {
      providerStates[index] = .loading(.cursor)
    }
    UsageCacheStore.save(providerStates)
    if hasStarted {
      connect(.cursor)
    }
  }

  func setAppLanguage(_ language: AppLanguage) {
    guard appLanguage != language else { return }
    AppLanguageStore.save(language)
    appLanguage = language
    configurationMessages = [:]
    diagnosticsMessage = nil
    providerStates = enabledProviderIDs.map(ProviderUsageState.loading)
    UsageCacheStore.save(providerStates)
    SettingsWindowController.shared.updateLocalization()
    UsageTrendWindowController.shared.updateLocalization()

    guard hasStarted else { return }
    for id in enabledProviderIDs {
      connect(id)
    }
  }

  func startIfNeeded() {
    guard !hasStarted, !isPreview else { return }
    hasStarted = true
    for id in enabledProviderIDs {
      connect(id)
    }
    checkForUpdates(manual: false)
    if preferences.notificationsEnabled { _ = notificationService }
    maintenanceTask = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
        self?.maintainUsage()
      }
    }
  }

  func refresh() {
    for id in enabledProviderIDs { refresh(id) }
  }

  func refresh(_ id: ProviderID) {
    guard !refreshingProviders.contains(id) else { return }
    guard let provider = providers[id] else {
      if hasStarted { connect(id) }
      return
    }
    refreshingProviders.insert(id)
    Task { [weak self] in
      await provider.refresh()
      self?.refreshingProviders.remove(id)
    }
  }

  func panelDidOpen() {
    refresh()
  }

  func redetectExecutables() {
    detectedExecutablePaths = Self.detectExecutables()
    configurationMessages = [:]
    guard hasStarted else { return }
    for id in enabledProviderIDs where [.codex, .claude, .kimi].contains(id) {
      connect(id)
    }
  }

  func setProviderEnabled(_ id: ProviderID, enabled: Bool) {
    let metadata = ProviderCatalog.metadata(for: id)
    guard case .available = metadata.availability else { return }

    if enabled {
      guard !enabledProviderIDs.contains(id) else { return }
      if id == .claude {
        do {
          try ClaudeStatusLineInstaller.install()
        } catch {
          configurationMessages[id] = configurationFailureMessage(
            error,
            providerID: id
          )
          return
        }
      }
      enabledProviderIDs.append(id)
      orderEnabledProviders()
      providerStates.append(.loading(id))
      orderStates()
      ProviderSettingsStore.setEnabledProviderIDs(enabledProviderIDs)
      if hasStarted {
        connect(id)
      }
      applyRefreshRoles()
    } else {
      guard enabledProviderIDs.count > 1 else { return }
      enabledProviderIDs.removeAll(where: { $0 == id })
      if primaryProviderID == id {
        primaryProviderID = enabledProviderIDs.first ?? .codex
        ProviderSettingsStore.setPrimaryProviderID(primaryProviderID)
      }
      orderEnabledProviders()
      ProviderSettingsStore.setEnabledProviderIDs(enabledProviderIDs)
      stop(id)
      providerStates.removeAll(where: { $0.id == id })
      configurationMessages[id] = nil
      if id == .claude {
        ClaudeStatusLineInstaller.uninstallIfOwned()
      }
      UsageCacheStore.save(providerStates)
      applyRefreshRoles()
    }
  }

  func testAndSaveAPIConfiguration(
    providerID: ProviderID,
    apiKey: String,
    organizationID: String = "",
    memberID: String = "",
    miniMaxRegion: MiniMaxRegion = .automatic
  ) {
    guard testingProviderID == nil else { return }
    let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedKey.isEmpty else {
      configurationMessages[providerID] = L10n.text(
        "error.enterAPIKey",
        "请输入 API Key"
      )
      return
    }

    testingProviderID = providerID
    configurationMessages[providerID] = L10n.text(
      "status.testingConnection",
      "正在测试连接"
    )
    Task {
      do {
        let state: ProviderUsageState
        switch providerID {
        case .cursor:
          guard cursorAccountMode == .teams else {
            throw ConfigurationError.unsupported
          }
          state = try await CursorUsageProviderFactory.fetch(apiKey: trimmedKey)
          try await KeychainAccessCoordinator.shared.write(
            trimmedKey,
            for: .cursorAdminAPIKey
          )
          credentialAvailability[providerID] = true
        case .minimax:
          state = try await MiniMaxUsageProviderFactory.fetch(
            apiKey: trimmedKey,
            region: miniMaxRegion
          )
          try await KeychainAccessCoordinator.shared.write(
            trimmedKey,
            for: .minimaxAPIKey
          )
          credentialAvailability[providerID] = true
          ProviderSettingsStore.setMiniMaxRegion(miniMaxRegion)
        case .deepseek:
          state = try await DeepSeekUsageProviderFactory.fetch(apiKey: trimmedKey)
          try await KeychainAccessCoordinator.shared.write(
            trimmedKey,
            for: .deepseekAPIKey
          )
          credentialAvailability[providerID] = true
        case .qoder:
          let configuration = QoderConfiguration(
            organizationID: organizationID.trimmingCharacters(in: .whitespacesAndNewlines),
            memberID: memberID.trimmingCharacters(in: .whitespacesAndNewlines)
          )
          guard !configuration.organizationID.isEmpty, !configuration.memberID.isEmpty else {
            throw ConfigurationError.missingQoderIDs
          }
          state = try await QoderUsageProviderFactory.fetch(
            apiKey: trimmedKey,
            configuration: configuration
          )
          try await KeychainAccessCoordinator.shared.write(
            trimmedKey,
            for: .qoderAPIKey
          )
          credentialAvailability[providerID] = true
          ProviderSettingsStore.setQoderConfiguration(configuration)
        default:
          throw ConfigurationError.unsupported
        }

        configurationMessages[providerID] = L10n.text(
          "status.configurationSaved",
          "连接正常，配置已保存"
        )
        testingProviderID = nil
        if !isProviderEnabled(providerID) {
          setProviderEnabled(providerID, enabled: true)
        }
        accept(state)
        if hasStarted {
          connect(providerID)
        }
      } catch {
        testingProviderID = nil
        configurationMessages[providerID] = configurationFailureMessage(
          error,
          providerID: providerID
        )
      }
    }
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    launchAtLoginError = nil
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    } catch {
      launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
      launchAtLoginError = error.localizedDescription
    }
  }

  func quit() {
    NSApplication.shared.terminate(nil)
  }

  func exportDiagnostics() {
    diagnosticsMessage = nil
    do {
      guard
        let url = try DiagnosticsExporter.export(
          states: providerStates,
          enabledProviderIDs: enabledProviderIDs,
          lowPowerModeEnabled: lowPowerModeEnabled,
          primaryProviderID: primaryProviderID
        )
      else {
        return
      }
      diagnosticsMessage = L10n.format(
        "diagnostics.exported",
        "诊断包已导出到 %@",
        url.lastPathComponent
      )
      DiagnosticLog.record("diagnostics_exported")
    } catch {
      diagnosticsMessage = error.localizedDescription
      DiagnosticLog.record("diagnostics_export_failed")
    }
  }

  func checkForUpdates(manual: Bool = true) {
    guard updateStatus != .checking else { return }
    if manual {
      updateStatus = .checking
    }
    Task {
      do {
        let result = try await updateChecker.check(
          currentVersion: currentVersion,
          force: manual
        )
        switch result {
        case .skipped:
          if manual {
            updateStatus = .upToDate
          }
        case .noRelease:
          updateStatus = .noRelease
        case .upToDate:
          updateStatus = .upToDate
        case .available(let version, let url):
          updateStatus = .available(version: version, url: url)
        }
      } catch {
        if manual {
          updateStatus = .failed
        }
        DiagnosticLog.record("update_check_failed")
      }
    }
  }

  func installAvailableUpdate() {
    guard case .available = updateStatus else { return }
    appUpdater.installAvailableUpdate()
  }

  func shutdown() async {
    guard !isShuttingDown else { return }
    isShuttingDown = true
    hasStarted = false
    maintenanceTask?.cancel()
    maintenanceTask = nil

    for task in startTasks.values {
      task.cancel()
    }
    for task in updateTasks.values {
      task.cancel()
    }
    startTasks.removeAll()
    updateTasks.removeAll()
    connectionGenerations.removeAll()

    let activeProviders = Array(providers.values)
    providers.removeAll()
    await withTaskGroup(of: Void.self) { group in
      for provider in activeProviders {
        group.addTask {
          await provider.stop()
        }
      }
    }
  }

  private func connect(_ id: ProviderID) {
    let previousProvider = detach(id)
    let generation = UUID()
    connectionGenerations[id] = generation
    let refreshRole = refreshRole(for: id)

    var loading = state(for: id) ?? .loading(id)
    loading.status = loading.defaultSummary == nil ? .loading : .stale
    loading.message = L10n.text("status.updating", "正在更新")
    loading.recoverySuggestion = nil
    accept(loading)

    startTasks[id] = Task { @MainActor [weak self] in
      if let previousProvider {
        await previousProvider.stop()
      }
      guard let self, !Task.isCancelled,
        connectionGenerations[id] == generation
      else {
        return
      }

      do {
        let provider = try await makeProvider(id)
        guard !Task.isCancelled, connectionGenerations[id] == generation else {
          await provider.stop()
          return
        }
        providers[id] = provider
        await provider.setRefreshRole(refreshRole)
        let stream = await provider.updates()
        guard connectionGenerations[id] == generation else {
          await provider.stop()
          return
        }
        updateTasks[id] = Task { @MainActor [weak self] in
          for await state in stream {
            guard !Task.isCancelled else { return }
            guard self?.connectionGenerations[id] == generation else { return }
            self?.accept(state)
          }
        }
        await provider.start()
      } catch {
        guard connectionGenerations[id] == generation else { return }
        let status: ProviderConnectionStatus =
          error is ConfigurationError ? .needsConfiguration : .error
        let state = (state(for: id) ?? .loading(id)).failed(
          status: status,
          message: error.localizedDescription,
          recoverySuggestion: ProviderRecoverySuggestion.text(
            for: error,
            providerID: id
          )
        )
        accept(state)
      }
    }
  }

  private func stop(_ id: ProviderID) {
    guard let provider = detach(id) else { return }
    Task {
      await provider.stop()
    }
  }

  private func detach(_ id: ProviderID) -> (any UsageProvider)? {
    startTasks[id]?.cancel()
    updateTasks[id]?.cancel()
    startTasks[id] = nil
    updateTasks[id] = nil
    connectionGenerations[id] = nil
    return providers.removeValue(forKey: id)
  }

  private func updatePowerState() {
    let enabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    guard lowPowerModeEnabled != enabled else { return }
    lowPowerModeEnabled = enabled
    DiagnosticLog.record(
      "power_mode_changed",
      fields: ["low_power": enabled ? "true" : "false"]
    )
    applyRefreshRoles()
    if !enabled {
      refreshPrimary()
    }
  }

  private func refreshPrimary() {
    guard
      let provider = providers[primaryProviderID]
    else {
      return
    }
    Task {
      await provider.refresh()
    }
  }

  private func applyRefreshRoles() {
    for (id, provider) in providers {
      let role = refreshRole(for: id)
      Task {
        await provider.setRefreshRole(role)
      }
    }
  }

  private func refreshRole(for id: ProviderID) -> ProviderRefreshRole {
    if id == primaryProviderID {
      return lowPowerModeEnabled && preferences.reduceInLowPower ? .lowPowerPrimary : .primary
    }
    return lowPowerModeEnabled && preferences.reduceInLowPower ? .suspended : .secondary
  }

  func updatePreferences(_ update: (inout MonitorPreferences) -> Void) {
    let old = preferences
    update(&preferences)
    if !isPreview { preferences.save() }
    if old.providerOrder != preferences.providerOrder {
      orderEnabledProviders()
      orderStates()
    }
    if old.appearance != preferences.appearance { applyAppearance() }
    if old.reduceInLowPower != preferences.reduceInLowPower { applyRefreshRoles() }
    if old.retentionDays != preferences.retentionDays {
      pruneHistory()
      persistHistory()
    }
  }

  func moveProvider(_ id: ProviderID, offset: Int) {
    var order = enabledProviderIDs
    guard let index = order.firstIndex(of: id), order.indices.contains(index + offset) else {
      return
    }
    order.swapAt(index, index + offset)
    updatePreferences { $0.providerOrder = order }
  }

  func setNotificationsEnabled(_ enabled: Bool) {
    notificationMessage = nil
    guard enabled else {
      updatePreferences { $0.notificationsEnabled = false }
      return
    }
    Task {
      do {
        let allowed = try await notificationService.requestPermission()
        updatePreferences { $0.notificationsEnabled = allowed }
        if !allowed {
          notificationMessage = NotificationPermissionError.denied.localizedDescription
        }
      } catch { notificationMessage = error.localizedDescription }
    }
  }

  func previewNotification() {
    guard preferences.notificationsEnabled else {
      notificationMessage = L10n.text("monitor.enableNotificationsFirst", "请先开启通知并授权。")
      return
    }
    Task {
      do {
        try await notificationService.post(
          provider: primaryProviderID,
          alerts: [
            UsageAlert(
              key: "preview", message: L10n.text("monitor.notificationPreview", "通知样式预览，不代表实际额度不足。")
            )
          ])
        notificationMessage = L10n.text("monitor.previewSent", "预览通知已发送")
      } catch { notificationMessage = error.localizedDescription }
    }
  }

  func clearHistory() {
    usageHistory = []
    usageEvents = []
    persistHistory()
    historyMessage = L10n.text("monitor.historyCleared", "本地历史已清除；后续成功刷新会继续记录。")
  }

  func exportHistory() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = "AI-Usage-History.csv"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try UsageHistoryInsights.csv(points: usageHistory, events: usageEvents).write(
        to: url, atomically: true, encoding: .utf8)
      historyMessage = L10n.format("monitor.historyExported", "历史已导出到 %@", url.lastPathComponent)
    } catch { historyMessage = error.localizedDescription }
  }

  func consumeCodexReset() {
    guard !resetInProgress, let provider = providers[.codex] as? CodexUsageProvider,
      let state = state(for: .codex), state.status == .connected,
      (state.resetCredits?.availableCount ?? 0) > 0
    else { return }
    resetInProgress = true
    resetMessage = L10n.text("monitor.resetting", "正在重置并重新查询额度…")
    let attemptKey = "codex-reset-attempt-" + (state.accountScope ?? "local")
    let key = UserDefaults.standard.string(forKey: attemptKey) ?? UUID().uuidString
    UserDefaults.standard.set(key, forKey: attemptKey)
    Task {
      defer { resetInProgress = false }
      do {
        let outcome = try await provider.consumeReset(idempotencyKey: key)
        switch outcome {
        case "reset", "alreadyRedeemed", "resetRefreshPending":
          UserDefaults.standard.removeObject(forKey: attemptKey)
          resetMessage =
            outcome == "resetRefreshPending"
            ? L10n.text("monitor.resetPendingRefresh", "重置已确认；额度读取失败，请点击刷新，勿重复使用次数。")
            : L10n.text("monitor.resetDone", "重置已确认，已重新查询额度。")
          usageEvents.append(
            UsageHistoryEvent(
              providerID: .codex, metricID: nil,
              accountScope: state.accountScope, date: .now, kind: .manualReset))
          persistHistory()
        case "nothingToReset":
          UserDefaults.standard.removeObject(forKey: attemptKey)
          resetMessage = L10n.text("monitor.nothingToReset", "当前没有可重置的额度，未消耗次数。")
        case "noCredit":
          UserDefaults.standard.removeObject(forKey: attemptKey)
          resetMessage = L10n.text("monitor.noResetCredit", "当前没有可用重置次数。")
        default:
          resetMessage = L10n.text("monitor.resetUncertain", "暂未确认重置结果；重试会沿用同一次请求。")
        }
      } catch {
        resetMessage =
          error.localizedDescription + "\n"
          + L10n.text("monitor.resetUncertain", "暂未确认重置结果；重试会沿用同一次请求。")
      }
    }
  }

  private func applyAppearance() {
    NSApp?.appearance =
      preferences.appearance == "dark"
      ? NSAppearance(named: .darkAqua)
      : preferences.appearance == "light" ? NSAppearance(named: .aqua) : nil
  }

  private func pruneHistory() {
    usageHistory = UsageHistoryStore.pruned(usageHistory, retentionDays: preferences.retentionDays)
    let cutoff = Date().addingTimeInterval(-Double(preferences.retentionDays) * 86_400)
    usageEvents = Array(usageEvents.filter { $0.date >= cutoff }.suffix(10_000))
  }

  private func persistHistory() {
    historyRevision += 1
    let points = usageHistory
    let events = usageEvents
    let revision = historyRevision
    Task { await usageHistoryWriter.save(points, events: events, revision: revision) }
  }

  private func evaluateAlerts(_ state: ProviderUsageState) {
    guard let updatedAt = state.updatedAt, Date().timeIntervalSince(updatedAt) <= 90 * 60 else {
      return
    }
    let alerts = alertEngine.evaluate(state, preferences: preferences).filter {
      !pendingAlerts.contains($0.key)
    }
    guard !alerts.isEmpty else { return }
    pendingAlerts.formUnion(alerts.map(\.key))
    Task {
      defer { pendingAlerts.subtract(alerts.map(\.key)) }
      do {
        guard preferences.notificationsEnabled, !preferences.isQuiet(at: Date()) else { return }
        try await notificationService.post(provider: state.id, alerts: alerts)
        alertEngine.markDelivered(alerts)
        if let data = try? JSONEncoder().encode(alertEngine.delivered) {
          UserDefaults.standard.set(data, forKey: "usage-alert-ledger")
        }
      } catch { notificationMessage = error.localizedDescription }
    }
  }

  private func maintainUsage() {
    guard hasStarted else { return }
    let now = Date()
    for state in providerStates {
      evaluateAlerts(state)
      for metric in state.metrics {
        guard let reset = metric.resetsAt, reset <= now,
          now.timeIntervalSince(reset) < 3_600
        else { continue }
        let key = MonitorPreferences.metricKey(providerID: state.id, metricID: metric.id)
        guard checkedResets[key] != reset else { continue }
        checkedResets[key] = reset
        refresh(state.id)
      }
    }
  }

  private func configurationFailureMessage(
    _ error: Error,
    providerID: ProviderID
  ) -> String {
    [
      error.localizedDescription,
      ProviderRecoverySuggestion.text(for: error, providerID: providerID),
    ].joined(separator: "\n")
  }

  private func makeProvider(_ id: ProviderID) async throws -> any UsageProvider {
    switch id {
    case .codex:
      guard let path = detectedExecutablePaths[.codex] else {
        throw ConfigurationError.executableNotFound("Codex CLI")
      }
      return CodexUsageProvider(executablePath: path)
    case .claude:
      guard detectedExecutablePaths[.claude] != nil else {
        throw ConfigurationError.executableNotFound("Claude Code")
      }
      try ClaudeStatusLineInstaller.install()
      return ClaudeUsageProviderFactory.make()
    case .kimi:
      guard detectedExecutablePaths[.kimi] != nil else {
        throw ConfigurationError.executableNotFound("Kimi Code")
      }
      return KimiUsageProviderFactory.make()
    case .cursor:
      if cursorAccountMode == .personal {
        return CursorUsageProviderFactory.makePersonal()
      }
      let key = await KeychainAccessCoordinator.shared.read(.cursorAdminAPIKey)
      credentialAvailability[id] = key != nil
      guard let key else {
        throw ConfigurationError.apiKeyRequired
      }
      return CursorUsageProviderFactory.makeTeams(apiKey: key)
    case .minimax:
      let key = await KeychainAccessCoordinator.shared.read(.minimaxAPIKey)
      credentialAvailability[id] = key != nil
      guard let key else {
        throw ConfigurationError.apiKeyRequired
      }
      return MiniMaxUsageProviderFactory.make(
        apiKey: key,
        region: ProviderSettingsStore.miniMaxRegion()
      )
    case .deepseek:
      let key = await KeychainAccessCoordinator.shared.read(.deepseekAPIKey)
      credentialAvailability[id] = key != nil
      guard let key else {
        throw ConfigurationError.apiKeyRequired
      }
      return DeepSeekUsageProviderFactory.make(apiKey: key)
    case .qoder:
      let key = await KeychainAccessCoordinator.shared.read(.qoderAPIKey)
      credentialAvailability[id] = key != nil
      guard let key else {
        throw ConfigurationError.apiKeyRequired
      }
      let configuration = ProviderSettingsStore.qoderConfiguration()
      guard !configuration.organizationID.isEmpty, !configuration.memberID.isEmpty else {
        throw ConfigurationError.missingQoderIDs
      }
      return QoderUsageProviderFactory.make(apiKey: key, configuration: configuration)
    case .ark, .aliyun, .tencent, .glm:
      throw ConfigurationError.unsupported
    }
  }

  private func accept(_ state: ProviderUsageState) {
    guard enabledProviderIDs.contains(state.id) else { return }
    let previous = self.state(for: state.id)
    let previousEventCount = usageEvents.count
    if state.id == .codex, state.status == .connected, !resetInProgress { resetMessage = nil }
    if !(state.id == .codex && resetInProgress) {
      usageEvents.append(
        contentsOf: UsageHistoryInsights.events(previous: previous, current: state))
    }
    if let index = providerStates.firstIndex(where: { $0.id == state.id }) {
      providerStates[index] = state
    } else {
      providerStates.append(state)
    }
    orderStates()
    UsageCacheStore.save(providerStates)
    if state.status == .connected {
      let updatedHistory = UsageHistoryStore.record(
        state, in: usageHistory, retentionDays: preferences.retentionDays)
      if updatedHistory != usageHistory || usageEvents.count != previousEventCount {
        usageHistory = updatedHistory
        pruneHistory()
        persistHistory()
      }
    }
    evaluateAlerts(state)
    DiagnosticLog.record(
      "provider_state",
      providerID: state.id,
      fields: [
        "metrics": String(state.metrics.count),
        "status": state.status.rawValue,
      ]
    )
  }

  private func orderEnabledProviders() {
    enabledProviderIDs = preferences.ordered(
      ProviderOrder.withPrimaryFirst(
        enabledProviderIDs,
        primary: primaryProviderID
      ))
  }

  private func orderStates() {
    providerStates.sort {
      enabledProviderIDs.firstIndex(of: $0.id)! < enabledProviderIDs.firstIndex(of: $1.id)!
    }
  }

  private func refreshCredentialAvailability() {
    Task { @MainActor [weak self] in
      let credentials: [(ProviderID, ProviderSecret)] = [
        (.cursor, .cursorAdminAPIKey),
        (.minimax, .minimaxAPIKey),
        (.deepseek, .deepseekAPIKey),
        (.qoder, .qoderAPIKey),
      ]
      for (providerID, secret) in credentials {
        guard let self else { return }
        let value = await KeychainAccessCoordinator.shared.read(secret)
        credentialAvailability[providerID] = value != nil
      }
    }
  }

  private static func detectExecutables() -> [ProviderID: String] {
    var result: [ProviderID: String] = [:]
    result[.codex] = CodexExecutableLocator.find()
    result[.claude] = ExecutableLocator.find(
      name: "claude",
      knownRelativePaths: [".local/bin/claude", ".claude/local/claude"]
    )
    result[.kimi] = ExecutableLocator.find(
      name: "kimi",
      knownRelativePaths: [".kimi-code/bin/kimi", ".local/bin/kimi"]
    )
    return result
  }

}

enum ConfigurationError: LocalizedError {
  case apiKeyRequired
  case missingQoderIDs
  case executableNotFound(String)
  case unsupported

  var errorDescription: String? {
    switch self {
    case .apiKeyRequired:
      return L10n.text("error.apiKeyRequired", "需要先配置 API Key")
    case .missingQoderIDs:
      return L10n.text(
        "error.qoderIDsRequired",
        "请填写 Organization ID 和 Member ID"
      )
    case .executableNotFound(let name):
      return L10n.format("error.executableNotFound", "未自动找到 %@", name)
    case .unsupported:
      return L10n.text("error.providerUnavailable", "该数据源暂不可用")
    }
  }
}

extension Notification.Name {
  static let aiUsageOpenPanel = Notification.Name("AIUsageOpenPanel")
}
