import AppKit
import SwiftUI

struct MenuBarContentView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(L10n.text("main.title", "AI 用量"))
          .font(.system(size: 13, weight: .semibold))
        Spacer()
        if model.lowPowerModeEnabled {
          Text(L10n.text("status.lowPowerMode", "低电量模式"))
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
        }
        Text(updateText)
          .font(.system(size: 10))
          .foregroundStyle(.tertiary)
      }
      .padding(.bottom, 14)

      ForEach(Array(model.providerStates.enumerated()), id: \.element.id) { index, state in
        ProviderUsageRow(state: state)
        if index < model.providerStates.count - 1 {
          Divider()
            .padding(.vertical, 8)
        }
      }

      if model.providerStates.isEmpty {
        Text(L10n.text("main.noProviders", "请在设置中选择要显示的数据源"))
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .padding(.vertical, 18)
      }

      Divider()
        .padding(.top, 14)
        .padding(.bottom, 8)

      HStack(spacing: 6) {
        footerButton(L10n.text("common.refresh", "刷新"), symbol: "arrow.clockwise") {
          model.refresh()
        }

        settingsControl

        Spacer()

        Button(L10n.text("common.quit", "退出")) {
          model.quit()
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      }
    }
    .padding(16)
    .frame(width: 350)
    .background(Color(nsColor: .windowBackgroundColor))
    .task {
      model.startIfNeeded()
    }
  }

  private var updateText: String {
    guard let date = model.primaryState.updatedAt else {
      return model.primaryState.status == .loading
        ? L10n.text("status.connecting", "连接中")
        : L10n.text("status.notUpdated", "尚未更新")
    }
    guard abs(date.timeIntervalSinceNow) >= 60 else {
      return L10n.text("status.updatedJustNow", "刚刚更新")
    }

    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  private func footerButton(
    _ title: String,
    symbol: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      MenuBarFooterButtonLabel(title: title, symbol: symbol)
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
  }

  private func openSettings() {
    SettingsWindowPresenter.live {
      SettingsWindowController.shared.show(model: model)
    }
    .present()
  }

  private var settingsControl: some View {
    footerButton(L10n.text("common.settings", "设置"), symbol: "gearshape") {
      openSettings()
    }
  }
}

private struct MenuBarFooterButtonLabel: View {
  let title: String
  let symbol: String

  var body: some View {
    Label(title, systemImage: symbol)
      .font(.system(size: 11))
      .padding(.horizontal, 6)
      .padding(.vertical, 6)
      .contentShape(Rectangle())
  }
}
