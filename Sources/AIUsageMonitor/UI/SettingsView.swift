import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel
  @State private var configurationProvider: ProviderID?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("AI 用量设置")
        .font(.system(size: 20, weight: .semibold))

      VStack(spacing: 0) {
        ForEach(ProviderCatalog.all) { metadata in
          providerRow(metadata)
          if metadata.id != ProviderCatalog.all.last?.id {
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
        Button("重新检测本机工具") {
          model.redetectExecutables()
        }
        .buttonStyle(.link)

        Spacer()

        Toggle(
          "登录时启动",
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
            Text("暂不可用")
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

      if metadata.configurationKind != .automatic, isAvailable(metadata) {
        Button(model.hasCredential(metadata.id) ? "配置" : "填写") {
          configurationProvider = metadata.id
        }
        .buttonStyle(.link)
        .font(.system(size: 10))
      }

      Toggle(
        "",
        isOn: Binding(
          get: { model.isProviderEnabled(metadata.id) },
          set: { enabled in
            if enabled, metadata.configurationKind != .automatic,
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
      .disabled(!isAvailable(metadata))
    }
    .padding(.vertical, 9)
  }

  private func rowDetail(_ metadata: ProviderMetadata) -> String {
    if let message = model.configurationMessages[metadata.id] {
      return message
    }
    if let path = model.detectedExecutablePaths[metadata.id] {
      return "已自动找到 · \(URL(fileURLWithPath: path).lastPathComponent)"
    }
    if metadata.configurationKind == .automatic,
      [.codex, .claude, .kimi].contains(metadata.id)
    {
      return "未自动找到"
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
}

private struct ProviderConfigurationView: View {
  @EnvironmentObject private var model: AppModel
  let providerID: ProviderID
  let onClose: () -> Void

  @State private var apiKey = ""
  @State private var organizationID = ""
  @State private var memberID = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("配置 \(ProviderCatalog.metadata(for: providerID).name)")
        .font(.system(size: 17, weight: .semibold))

      SecureField("API Key", text: $apiKey)
        .textFieldStyle(.roundedBorder)

      if providerID == .qoder {
        TextField("Organization ID", text: $organizationID)
          .textFieldStyle(.roundedBorder)
        TextField("Member ID", text: $memberID)
          .textFieldStyle(.roundedBorder)
      }

      Text("凭证仅保存在本机 macOS 钥匙串；测试成功后才会保存。")
        .font(.system(size: 10))
        .foregroundStyle(.secondary)

      if let message = model.configurationMessages[providerID] {
        Text(message)
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      }

      HStack {
        Button("取消", action: onClose)
        Spacer()
        Button("保存并测试") {
          model.testAndSaveAPIConfiguration(
            providerID: providerID,
            apiKey: apiKey,
            organizationID: organizationID,
            memberID: memberID
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
    }
  }
}
