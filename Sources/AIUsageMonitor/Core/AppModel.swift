import AppKit
import Foundation
import ServiceManagement

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

  var currentVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
      as? String ?? "0.0.0"
  }

  private var providers: [ProviderID: any UsageProvider] = [:]
  private let appUpdater = AppUpdater()
  private let updateChecker = UpdateChecker()
  private let usageHistoryWriter = UsageHistoryWriter()
  private var updateTasks: [ProviderID: Task<Void, Never>] = [:]
  private var startTasks: [ProviderID: Task<Void, Never>] = [:]
  private var connectionGenerations: [ProviderID: UUID] = [:]
  private var powerStateObserver: NSObjectProtocol?
  private var wakeObserver: NSObjectProtocol?
  private var hasStarted = false
  private var isShuttingDown = false

  init() {
    appLanguage = AppLanguageStore.load()
    var enabled = ProviderSettingsStore.enabledProviderIDs()
    let primary = ProviderSettingsStore.primaryProviderID(
      enabledProviderIDs: enabled
    )
    enabled = ProviderOrder.withPrimaryFirst(enabled, primary: primary)
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
    usageHistory = UsageHistoryStore.load()

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
        self?.refreshPrimary()
      }
    }
    refreshCredentialAvailability()
  }

  deinit {
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
    guard !hasStarted else { return }
    hasStarted = true
    for id in enabledProviderIDs {
      connect(id)
    }
    checkForUpdates(manual: false)
  }

  func refresh() {
    let activeProviders = Array(providers.values)
    Task {
      await withTaskGroup(of: Void.self) { group in
        for provider in activeProviders {
          group.addTask { await provider.refresh() }
        }
      }
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
          lowPowerModeEnabled: lowPowerModeEnabled
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
      return lowPowerModeEnabled ? .lowPowerPrimary : .primary
    }
    return lowPowerModeEnabled ? .suspended : .secondary
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
    if let index = providerStates.firstIndex(where: { $0.id == state.id }) {
      providerStates[index] = state
    } else {
      providerStates.append(state)
    }
    orderStates()
    UsageCacheStore.save(providerStates)
    if state.status == .connected {
      let updatedHistory = UsageHistoryStore.record(state, in: usageHistory)
      if updatedHistory != usageHistory {
        usageHistory = updatedHistory
        Task {
          await usageHistoryWriter.save(updatedHistory)
        }
      }
    }
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
    enabledProviderIDs = ProviderOrder.withPrimaryFirst(
      enabledProviderIDs,
      primary: primaryProviderID
    )
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
