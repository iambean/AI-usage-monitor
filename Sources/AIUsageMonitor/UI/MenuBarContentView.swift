import AppKit
import SwiftUI

struct MenuBarContentView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("AI 用量")
          .font(.system(size: 13, weight: .semibold))
        Spacer()
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
        Text("请在设置中选择要显示的数据源")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .padding(.vertical, 18)
      }

      Divider()
        .padding(.top, 14)
        .padding(.bottom, 8)

      HStack(spacing: 6) {
        footerButton("刷新", symbol: "arrow.clockwise") {
          model.refresh()
        }

        settingsControl

        Spacer()

        Button("退出") {
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
      return model.primaryState.status == .loading ? "连接中" : "尚未更新"
    }
    guard abs(date.timeIntervalSinceNow) >= 60 else {
      return "刚刚更新"
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
      Label(title, systemImage: symbol)
        .font(.system(size: 11))
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
    .padding(.vertical, 3)
    .padding(.trailing, 8)
  }

  private func openSettings() {
    SettingsWindowPresenter.live {
      NSApp.sendAction(
        Selector(("showSettingsWindow:")),
        to: nil,
        from: nil
      )
    }
    .present()
  }

  @ViewBuilder
  private var settingsControl: some View {
    if #available(macOS 14.0, *) {
      FocusedSettingsButton()
    } else {
      footerButton("设置", symbol: "gearshape") {
        openSettings()
      }
    }
  }
}

@available(macOS 14.0, *)
private struct FocusedSettingsButton: View {
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Button {
      SettingsWindowPresenter.live {
        openSettings()
      }
      .present()
    } label: {
      Label("设置", systemImage: "gearshape")
        .font(.system(size: 11))
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
    .padding(.vertical, 3)
    .padding(.trailing, 8)
  }
}
