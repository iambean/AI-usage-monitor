import AppKit
import SwiftUI

struct MenuBarContentView: View {
  @EnvironmentObject private var model: AppModel
  @State private var sectionHeights: [MenuSection: CGFloat] = [:]
  var maximumHeight: CGFloat = .infinity
  var onContentHeightChange: ((CGFloat) -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header.background(measure(.header))
      ScrollView(.vertical, showsIndicators: needsScrolling) {
        providerList
          .fixedSize(horizontal: false, vertical: true)
          .background(measure(.providers))
      }
      .frame(height: providerViewportHeight)
      .scrollDisabled(!needsScrolling)
      footer.background(measure(.footer))
    }
    .padding(16)
    .frame(width: MenuPanelGeometry.width)
    .fixedSize(horizontal: false, vertical: true)
    .background(Color(nsColor: .windowBackgroundColor))
    .onPreferenceChange(MenuSectionHeightsKey.self) { sectionHeights = $0 }
    .background {
      GeometryReader { geometry in
        Color.clear.preference(key: MenuBarContentHeightKey.self, value: geometry.size.height)
      }
    }
    .onPreferenceChange(MenuBarContentHeightKey.self) { onContentHeightChange?($0) }
    .task { model.startIfNeeded() }
  }

  private var providerHeight: CGFloat { sectionHeights[.providers] ?? 1 }
  private var providerViewportHeight: CGFloat {
    let chromeHeight = 32 + (sectionHeights[.header] ?? 0) + (sectionHeights[.footer] ?? 0)
    return min(providerHeight, max(0, maximumHeight - chromeHeight))
  }
  private var needsScrolling: Bool { providerHeight > providerViewportHeight + 0.5 }

  private var header: some View {
    HStack {
      Text(L10n.text("main.title", "AI 用量"))
        .font(.system(size: 13, weight: .semibold))
      Spacer()
      if model.lowPowerModeEnabled {
        Text(L10n.text("status.lowPowerMode", "低电量模式"))
          .font(.system(size: 9)).foregroundStyle(.tertiary)
      }
      Text(updateText).font(.system(size: 10)).foregroundStyle(.tertiary)
    }
    .padding(.bottom, 14)
  }

  private var providerList: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(model.providerStates.enumerated()), id: \.element.id) { index, state in
        ProviderUsageRow(
          state: state,
          selectedMetricID: model.preferences.selectedMetrics[state.id.rawValue],
          compact: model.preferences.compact,
          isCollapsed: model.preferences.collapsedProviders.contains(state.id),
          isRefreshing: model.refreshingProviders.contains(state.id),
          onToggle: {
            model.updatePreferences { preferences in
              if preferences.collapsedProviders.contains(state.id) {
                preferences.collapsedProviders.removeAll { $0 == state.id }
              } else {
                preferences.collapsedProviders.append(state.id)
              }
            }
          },
          onRefresh: { model.refresh(state.id) },
          onReset: state.id == .codex ? { model.consumeCodexReset() } : nil,
          resetInProgress: model.resetInProgress,
          resetMessage: state.id == .codex ? model.resetMessage : nil
        )
        if index < model.providerStates.count - 1 { Divider().padding(.vertical, 8) }
      }
      if model.providerStates.isEmpty {
        Text(L10n.text("main.noProviders", "请在设置中选择要显示的数据源"))
          .font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 18)
      }
    }
  }

  private var footer: some View {
    VStack(spacing: 0) {
      Divider().padding(.top, 14).padding(.bottom, 8)
      HStack(spacing: 6) {
        footerButton(L10n.text("common.refresh", "刷新"), symbol: "arrow.clockwise") {
          model.refresh()
        }
        footerButton(L10n.text("common.trends", "趋势"), symbol: "chart.line.uptrend.xyaxis") {
          UsageTrendWindowController.shared.show(model: model)
        }
        footerButton(L10n.text("common.settings", "设置"), symbol: "gearshape") {
          SettingsWindowPresenter.live { SettingsWindowController.shared.show(model: model) }
            .present()
        }
        Spacer()
        Button(L10n.text("common.quit", "退出")) { model.quit() }
          .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
      }
    }
  }

  private func measure(_ section: MenuSection) -> some View {
    GeometryReader { geometry in
      Color.clear.preference(
        key: MenuSectionHeightsKey.self, value: [section: geometry.size.height])
    }
  }

  private var updateText: String {
    if !model.refreshingProviders.isEmpty { return L10n.text("status.updating", "正在更新") }
    let connected = model.providerStates.filter { $0.status == .connected }.count
    return L10n.format(
      "monitor.connectedCount", "%d / %d 个服务已连接", connected, model.providerStates.count)
  }

  private func footerButton(_ title: String, symbol: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) { MenuBarFooterButtonLabel(title: title, symbol: symbol) }
      .buttonStyle(.plain).foregroundStyle(.secondary)
  }
}

private enum MenuSection: Hashable { case header, providers, footer }
private struct MenuSectionHeightsKey: PreferenceKey {
  static let defaultValue: [MenuSection: CGFloat] = [:]
  static func reduce(value: inout [MenuSection: CGFloat], nextValue: () -> [MenuSection: CGFloat]) {
    value.merge(nextValue(), uniquingKeysWith: { max($0, $1) })
  }
}
private struct MenuBarContentHeightKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}
private struct MenuBarFooterButtonLabel: View {
  let title: String
  let symbol: String
  var body: some View {
    Label(title, systemImage: symbol)
      .font(.system(size: 11)).padding(.horizontal, 6).padding(.vertical, 6).contentShape(
        Rectangle())
  }
}
