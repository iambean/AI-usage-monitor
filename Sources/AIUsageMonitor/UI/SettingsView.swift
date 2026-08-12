import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel
  @State private var configurationProvider: ProviderID?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(L10n.text("settings.title", "AI 用量设置"))
        .font(.system(size: 20, weight: .semibold))

      VStack(spacing: 0) {
        ForEach(orderedProviders) { metadata in
          providerRow(metadata)
          if metadata.id != orderedProviders.last?.id {
            Divider()
              .padding(.leading, 38)
          }
        }
      }
      .padding(.horizontal, 12)
      .background(
        RoundedRectangle(cornerRadius: 10)
          .fill(Color.primary.opacity(0.045))
      )

      HStack {
        Button(L10n.text("settings.redetect", "重新检测本机工具")) {
          model.redetectExecutables()
        }
        .buttonStyle(.link)

        Button(L10n.text("diagnostics.export", "导出诊断")) {
          model.exportDiagnostics()
        }
        .buttonStyle(.link)

        Spacer()

        Picker(
          L10n.text("settings.language", "语言"),
          selection: Binding(
            get: { model.appLanguage },
            set: { model.setAppLanguage($0) }
          )
        ) {
          ForEach(AppLanguage.allCases) { language in
            Text(language.title).tag(language)
          }
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .fixedSize()
        .id(model.appLanguage)

        Toggle(
          L10n.text("settings.launchAtLogin", "登录时启动"),
          isOn: Binding(
            get: { model.launchAtLoginEnabled },
            set: { model.setLaunchAtLogin($0) }
          )
        )
        .toggleStyle(.switch)
      }

      if let error = model.launchAtLoginError {
        Text(error)
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      }

      if let message = model.diagnosticsMessage {
        Text(message)
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      }

      softwareUpdateSection
    }
    .padding(24)
    .frame(width: 560)
    .sheet(
      isPresented: Binding(
        get: { configurationProvider != nil },
        set: { if !$0 { configurationProvider = nil } }
      )
    ) {
      if let configurationProvider {
        ProviderConfigurationView(providerID: configurationProvider) {
          self.configurationProvider = nil
        }
        .environmentObject(model)
      }
    }
  }

  @ViewBuilder
  private func providerRow(_ metadata: ProviderMetadata) -> some View {
    HStack(spacing: 10) {
      ProviderIcon(
        providerID: metadata.id,
        fallbackSymbolName: metadata.symbolName,
        size: 23
      )
      .frame(width: 22)
      .opacity(isAvailable(metadata) ? 1 : 0.35)

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(metadata.name)
            .font(.system(size: 12, weight: .semibold))
          if case .unavailable = metadata.availability {
            Text(L10n.text("status.temporarilyUnavailable", "暂不可用"))
              .font(.system(size: 9, weight: .medium))
              .foregroundStyle(.secondary)
              .padding(.horizontal, 5)
              .padding(.vertical, 2)
              .background(Capsule().fill(Color.primary.opacity(0.08)))
          }
        }
        Text(rowDetail(metadata))
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      if metadata.id == .cursor {
        Picker(
          "",
          selection: Binding(
            get: { model.cursorAccountMode },
            set: { model.setCursorAccountMode($0) }
          )
        ) {
          ForEach(CursorAccountMode.allCases, id: \.self) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 118)
        .id(model.appLanguage)
      }

      if requiresCredential(metadata), isAvailable(metadata) {
        Button(
          model.hasCredential(metadata.id)
            ? L10n.text("common.configure", "配置")
            : L10n.text("common.enter", "填写")
        ) {
          configurationProvider = metadata.id
        }
        .buttonStyle(.link)
        .font(.system(size: 10))
      }

      if isAvailable(metadata) {
        Button {
          model.setPrimaryProvider(metadata.id)
        } label: {
          Image(
            systemName: model.isPrimaryProvider(metadata.id)
              ? "star.fill"
              : "star"
          )
          .font(.system(size: 11, weight: .medium))
          .frame(width: 22, height: 22)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(
          model.isPrimaryProvider(metadata.id)
            ? Color.accentColor
            : Color.secondary
        )
        .disabled(!model.isProviderEnabled(metadata.id))
        .help(
          model.isPrimaryProvider(metadata.id)
            ? L10n.text("settings.defaultProvider", "默认项")
            : L10n.text("settings.makeDefault", "设为默认项")
        )
        .accessibilityLabel(
          model.isPrimaryProvider(metadata.id)
            ? L10n.text("settings.defaultProvider", "默认项")
            : L10n.text("settings.makeDefault", "设为默认项")
        )
      }

      Toggle(
        "",
        isOn: Binding(
          get: { model.isProviderEnabled(metadata.id) },
          set: { enabled in
            if enabled, requiresCredential(metadata),
              !model.hasCredential(metadata.id)
            {
              configurationProvider = metadata.id
            } else {
              model.setProviderEnabled(metadata.id, enabled: enabled)
            }
          }
        )
      )
      .labelsHidden()
      .toggleStyle(.switch)
      .controlSize(.small)
      .disabled(
        !isAvailable(metadata)
          || (model.isPrimaryProvider(metadata.id) && model.enabledProviderIDs.count == 1)
      )
    }
    .padding(.vertical, 9)
  }

  private func rowDetail(_ metadata: ProviderMetadata) -> String {
    if let message = model.configurationMessages[metadata.id] {
      return message
    }
    if case .unavailable(let reason) = metadata.availability {
      return reason
    }
    if metadata.id == .cursor, model.cursorAccountMode == .personal {
      return L10n.text(
        "provider.cursor.personalDetail",
        "个人版仅支持打开官方 Usage 页面"
      )
    }
    if let path = model.detectedExecutablePaths[metadata.id] {
      return L10n.format(
        "settings.detectedTool",
        "已自动找到 · %@",
        URL(fileURLWithPath: path).lastPathComponent
      )
    }
    if metadata.configurationKind == .automatic,
      [.codex, .claude, .kimi].contains(metadata.id)
    {
      return L10n.text("settings.toolNotFound", "未自动找到")
    }
    if let state = model.state(for: metadata.id), let message = state.message {
      return message
    }
    return metadata.detail
  }

  private func isAvailable(_ metadata: ProviderMetadata) -> Bool {
    if case .available = metadata.availability { return true }
    return false
  }

  private var orderedProviders: [ProviderMetadata] {
    let primary = ProviderCatalog.metadata(for: model.primaryProviderID)
    return [primary] + ProviderCatalog.all.filter { $0.id != primary.id }
  }

  private func requiresCredential(_ metadata: ProviderMetadata) -> Bool {
    if metadata.id == .cursor {
      return model.cursorAccountMode == .teams
    }
    return metadata.configurationKind != .automatic
  }

  private var softwareUpdateSection: some View {
    HStack(spacing: 10) {
      Image(systemName: updateSymbolName)
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(updateSymbolColor)
        .frame(width: 22)

      VStack(alignment: .leading, spacing: 2) {
        Text(L10n.text("update.title", "软件更新"))
          .font(.system(size: 11, weight: .semibold))
        Text(updateDetailText)
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      }

      Spacer()
      updateAction
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(Color.primary.opacity(0.045))
    )
  }

  @ViewBuilder
  private var updateAction: some View {
    switch model.updateStatus {
    case .checking:
      ProgressView()
        .controlSize(.small)
    case .available:
      Button(L10n.text("update.download", "前往下载")) {
        model.openAvailableUpdate()
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
    case .failed:
      Button(L10n.text("update.retry", "重试")) {
        model.checkForUpdates()
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    case .idle:
      updateCheckButton(title: L10n.text("update.check", "检查更新"))
    case .noRelease, .upToDate:
      updateCheckButton(title: L10n.text("update.recheck", "重新检查"))
    }
  }

  private func updateCheckButton(title: String) -> some View {
    Button(title) {
      model.checkForUpdates()
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
  }

  private var updateDetailText: String {
    switch model.updateStatus {
    case .idle:
      return L10n.format("update.currentVersion", "当前版本 %@", model.currentVersion)
    case .checking:
      return L10n.text("update.checking", "正在检查新版本…")
    case .noRelease:
      return L10n.format(
        "update.noRelease",
        "当前版本 %@ · 尚无发布版本",
        model.currentVersion
      )
    case .upToDate:
      return L10n.format(
        "update.upToDate",
        "当前版本 %@ · 已是最新",
        model.currentVersion
      )
    case .available(let version, _):
      return L10n.format(
        "update.available",
        "当前版本 %@ · 可更新至 %@",
        model.currentVersion,
        version
      )
    case .failed:
      return L10n.format(
        "update.checkFailedDetail",
        "当前版本 %@ · 检查失败，请稍后重试",
        model.currentVersion
      )
    }
  }

  private var updateSymbolName: String {
    switch model.updateStatus {
    case .idle, .checking:
      return "arrow.triangle.2.circlepath"
    case .noRelease:
      return "shippingbox"
    case .upToDate:
      return "checkmark.circle.fill"
    case .available:
      return "arrow.down.circle.fill"
    case .failed:
      return "exclamationmark.triangle.fill"
    }
  }

  private var updateSymbolColor: Color {
    switch model.updateStatus {
    case .checking, .available:
      return .accentColor
    case .upToDate:
      return .green
    case .failed:
      return .orange
    case .idle, .noRelease:
      return .secondary
    }
  }
}

private struct ProviderConfigurationView: View {
  @EnvironmentObject private var model: AppModel
  let providerID: ProviderID
  let onClose: () -> Void

  @State private var apiKey = ""
  @State private var organizationID = ""
  @State private var memberID = ""
  @State private var miniMaxRegion = MiniMaxRegion.automatic

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(
        L10n.format(
          "settings.configureProvider",
          "配置 %@",
          ProviderCatalog.metadata(for: providerID).name
        )
      )
      .font(.system(size: 17, weight: .semibold))

      SecureField(
        providerID == .cursor ? "Cursor Admin API Key" : "API Key",
        text: $apiKey
      )
      .textFieldStyle(.roundedBorder)

      if providerID == .cursor {
        Text(
          L10n.text(
            "settings.cursorAdminKeyHelp",
            "仅支持 Cursor Teams 管理员密钥；请在 Cursor Dashboard → Settings → Cursor Admin API Keys 中创建。"
          )
        )
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
      }

      if providerID == .minimax {
        Picker(
          L10n.text("settings.serviceRegion", "服务区域"),
          selection: $miniMaxRegion
        ) {
          ForEach(MiniMaxRegion.allCases, id: \.self) { region in
            Text(region.title).tag(region)
          }
        }
      }

      if providerID == .qoder {
        TextField("Organization ID", text: $organizationID)
          .textFieldStyle(.roundedBorder)
        TextField("Member ID", text: $memberID)
          .textFieldStyle(.roundedBorder)
      }

      Text(
        L10n.text(
          "settings.credentialNotice",
          "凭证仅保存在本机 macOS 钥匙串；测试成功后才会保存。"
        )
      )
      .font(.system(size: 10))
      .foregroundStyle(.secondary)

      if let message = model.configurationMessages[providerID] {
        Text(message)
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      }

      HStack {
        Button(L10n.text("common.cancel", "取消"), action: onClose)
        Spacer()
        Button(L10n.text("settings.saveAndTest", "保存并测试")) {
          model.testAndSaveAPIConfiguration(
            providerID: providerID,
            apiKey: apiKey,
            organizationID: organizationID,
            memberID: memberID,
            miniMaxRegion: miniMaxRegion
          )
        }
        .keyboardShortcut(.defaultAction)
        .disabled(model.testingProviderID != nil)
      }
    }
    .padding(22)
    .frame(width: 420)
    .onAppear {
      if providerID == .qoder {
        organizationID = model.qoderConfiguration.organizationID
        memberID = model.qoderConfiguration.memberID
      }
      if providerID == .minimax {
        miniMaxRegion = model.miniMaxRegion
      }
    }
  }
}
