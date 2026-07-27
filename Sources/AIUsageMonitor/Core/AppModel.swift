import AppKit
import Foundation
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var providerStates: [ProviderUsageState]
  @Published private(set) var enabledProviderIDs: [ProviderID]
  @Published private(set) var launchAtLoginEnabled: Bool
  @Published private(set) var launchAtLoginError: String?
  @Published private(set) var detectedExecutablePaths: [ProviderID: String]
  @Published private(set) var configurationMessages: [ProviderID: String] = [:]
  @Published private(set) var testingProviderID: ProviderID?

  private var providers: [ProviderID: any UsageProvider] = [:]
  private var updateTasks: [ProviderID: Task<Void, Never>] = [:]
  private var startTasks: [ProviderID: Task<Void, Never>] = [:]
  private var hasStarted = false

  init() {
    let enabled = ProviderSettingsStore.enabledProviderIDs()
    enabledProviderIDs = enabled
    let cached = UsageCacheStore.load()
    providerStates = enabled.map { id in
      cached.first(where: { $0.id == id }) ?? .loading(id)
    }
    launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    detectedExecutablePaths = Self.detectExecutables()
  }

  deinit {
    startTasks.values.forEach { $0.cancel() }
    updateTasks.values.forEach { $0.cancel() }
  }

  var primaryState: ProviderUsageState {
    providerStates.first ?? .loading(.codex)
  }

  var qoderConfiguration: QoderConfiguration {
    ProviderSettingsStore.qoderConfiguration()
  }

  func isProviderEnabled(_ id: ProviderID) -> Bool {
    enabledProviderIDs.contains(id)
  }

  func hasCredential(_ id: ProviderID) -> Bool {
    switch id {
    case .minimax:
      return KeychainStore.read(.minimaxAPIKey) != nil
    case .deepseek:
      return KeychainStore.read(.deepseekAPIKey) != nil
    case .qoder:
      return KeychainStore.read(.qoderAPIKey) != nil
    default:
      return true
    }
  }

  func state(for id: ProviderID) -> ProviderUsageState? {
    providerStates.first(where: { $0.id == id })
  }

  func startIfNeeded() {
    guard !hasStarted else { return }
    hasStarted = true
    for id in enabledProviderIDs {
      connect(id)
    }
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
          configurationMessages[id] = error.localizedDescription
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
    } else {
      enabledProviderIDs.removeAll(where: { $0 == id })
      ProviderSettingsStore.setEnabledProviderIDs(enabledProviderIDs)
      stop(id)
      providerStates.removeAll(where: { $0.id == id })
      configurationMessages[id] = nil
      if id == .claude {
        ClaudeStatusLineInstaller.uninstallIfOwned()
      }
      UsageCacheStore.save(providerStates)
    }
  }

  func testAndSaveAPIConfiguration(
    providerID: ProviderID,
    apiKey: String,
    organizationID: String = "",
    memberID: String = ""
  ) {
    guard testingProviderID == nil else { return }
    let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedKey.isEmpty else {
      configurationMessages[providerID] = "请输入 API Key"
      return
    }

    testingProviderID = providerID
    configurationMessages[providerID] = "正在测试连接"
    Task {
      do {
        let state: ProviderUsageState
        switch providerID {
        case .minimax:
          state = try await MiniMaxUsageProviderFactory.fetch(apiKey: trimmedKey)
          try KeychainStore.write(trimmedKey, for: .minimaxAPIKey)
        case .deepseek:
          state = try await DeepSeekUsageProviderFactory.fetch(apiKey: trimmedKey)
          try KeychainStore.write(trimmedKey, for: .deepseekAPIKey)
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
          try KeychainStore.write(trimmedKey, for: .qoderAPIKey)
          ProviderSettingsStore.setQoderConfiguration(configuration)
        default:
          throw ConfigurationError.unsupported
        }

        configurationMessages[providerID] = "连接正常，配置已保存"
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
        configurationMessages[providerID] = error.localizedDescription
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

  private func connect(_ id: ProviderID) {
    stop(id)

    do {
      let provider = try makeProvider(id)
      providers[id] = provider

      var loading = state(for: id) ?? .loading(id)
      loading.status = loading.summary == nil ? .loading : .stale
      loading.message = "正在更新"
      accept(loading)

      startTasks[id] = Task {
        let stream = await provider.updates()
        updateTasks[id] = Task { @MainActor [weak self] in
          for await state in stream {
            guard !Task.isCancelled else { return }
            self?.accept(state)
          }
        }
        await provider.start()
      }
    } catch {
      var state = state(for: id) ?? .loading(id)
      state.status =
        error is ConfigurationError ? .needsConfiguration : .error
      state.message = error.localizedDescription
      accept(state)
    }
  }

  private func stop(_ id: ProviderID) {
    startTasks[id]?.cancel()
    updateTasks[id]?.cancel()
    startTasks[id] = nil
    updateTasks[id] = nil
    if let provider = providers.removeValue(forKey: id) {
      Task { await provider.stop() }
    }
  }

  private func makeProvider(_ id: ProviderID) throws -> any UsageProvider {
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
    case .minimax:
      guard let key = KeychainStore.read(.minimaxAPIKey) else {
        throw ConfigurationError.apiKeyRequired
      }
      return MiniMaxUsageProviderFactory.make(apiKey: key)
    case .deepseek:
      guard let key = KeychainStore.read(.deepseekAPIKey) else {
        throw ConfigurationError.apiKeyRequired
      }
      return DeepSeekUsageProviderFactory.make(apiKey: key)
    case .qoder:
      guard let key = KeychainStore.read(.qoderAPIKey) else {
        throw ConfigurationError.apiKeyRequired
      }
      let configuration = ProviderSettingsStore.qoderConfiguration()
      guard !configuration.organizationID.isEmpty, !configuration.memberID.isEmpty else {
        throw ConfigurationError.missingQoderIDs
      }
      return QoderUsageProviderFactory.make(apiKey: key, configuration: configuration)
    case .glm:
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
  }

  private func orderEnabledProviders() {
    enabledProviderIDs.sort {
      let order = ProviderCatalog.all.map(\.id)
      return order.firstIndex(of: $0)! < order.firstIndex(of: $1)!
    }
  }

  private func orderStates() {
    providerStates.sort {
      enabledProviderIDs.firstIndex(of: $0.id)! < enabledProviderIDs.firstIndex(of: $1.id)!
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
      return "需要先配置 API Key"
    case .missingQoderIDs:
      return "请填写 Organization ID 和 Member ID"
    case .executableNotFound(let name):
      return "未自动找到 \(name)"
    case .unsupported:
      return "该数据源暂不可用"
    }
  }
}
