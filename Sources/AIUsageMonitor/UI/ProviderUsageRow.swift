import AppKit
import SwiftUI

struct ProviderUsageRow: View {
  let state: ProviderUsageState
  var selectedMetricID: String?
  var compact = false
  var isCollapsed = false
  var isRefreshing = false
  var onToggle: (() -> Void)?
  var onRefresh: (() -> Void)?
  var onReset: (() -> Void)?
  var resetInProgress = false
  var resetMessage: String?
  @State private var resetCreditsExpanded = false
  @State private var confirmReset = false

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      VStack(alignment: .leading, spacing: compact ? 6 : 9) {
        header
        HStack(spacing: 6) {
          Text(sourceLabel)
            .lineLimit(1)
            .help(sourceLabel)
          Spacer(minLength: 3)
          Text(
            isRefreshing
              ? L10n.text("status.updating", "正在更新")
              : UsagePresentation.updatedText(state.updatedAt, now: context.date)
          )
          .fixedSize()
          if let onRefresh {
            Button(action: onRefresh) {
              Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
            .accessibilityLabel(L10n.format("monitor.refreshProvider", "刷新 %@", state.name))
          }
        }
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
        if !isCollapsed {
          if state.status != .connected || state.metrics.isEmpty {
            statusContent
          }
          if canShowUsage {
            if !(state.metrics.count == 1 && state.metrics.first?.value.kind == .balance) {
              metricsContent(now: context.date)
            }
            if state.id == .codex {
              CodexResetCreditsView(
                credits: state.resetCredits, isStale: state.status == .stale,
                isExpanded: $resetCreditsExpanded)
              if resetCreditsExpanded, let onReset,
                state.status == .connected, (state.resetCredits?.availableCount ?? 0) > 0
              {
                Button(
                  resetInProgress
                    ? L10n.text("monitor.resetting", "正在重置并重新查询额度…")
                    : L10n.text("monitor.useReset", "使用一次重置…")
                ) { confirmReset = true }
                .buttonStyle(.link)
                .font(.system(size: 10))
                .disabled(resetInProgress)
                .alert(
                  L10n.text("monitor.confirmResetTitle", "使用一次重置？"), isPresented: $confirmReset
                ) {
                  Button(L10n.text("common.cancel", "取消"), role: .cancel) {}
                  Button(
                    L10n.text("monitor.confirmReset", "确认使用"), role: .destructive, action: onReset)
                } message: {
                  Text(L10n.text("monitor.confirmResetBody", "这将消耗 1 次可用重置。完成后重新查询额度与剩余次数。"))
                }
              }
              if let resetMessage {
                Text(resetMessage).font(.system(size: 10)).foregroundStyle(.secondary)
              }
            }
          }
        }
      }
      .padding(.vertical, compact ? 3 : 5)
    }
    .onChange(of: state.accountScope) { _ in
      resetCreditsExpanded = false
      confirmReset = false
    }
  }

  private var sourceLabel: String {
    if let label = state.accountLabel { return label }
    guard canShowUsage else { return ProviderCatalog.metadata(for: state.id).detail }
    if [.codex, .kimi, .claude].contains(state.id) {
      return L10n.text("monitor.localSource", "本机用量数据")
    }
    return state.metrics.isEmpty
      ? ProviderCatalog.metadata(for: state.id).detail
      : L10n.text("monitor.apiSource", "API 用量数据")
  }

  private var metric: UsageMetric? { state.selectedMetric(selectedMetricID) }
  private var canShowUsage: Bool { state.status == .connected || state.status == .stale }

  private var header: some View {
    HStack(spacing: 7) {
      if let onToggle {
        Button(action: onToggle) {
          Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
            .font(.system(size: 8, weight: .medium))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.format("monitor.toggleProvider", "展开或折叠 %@", state.name))
      }
      Link(destination: ProviderUsageDestination.url(for: state.id)) {
        HStack(spacing: 8) {
          ProviderIcon(providerID: state.id, fallbackSymbolName: state.symbolName, size: 24)
          Text(state.name).font(.system(size: 14, weight: .semibold))
        }
      }
      .buttonStyle(.plain)
      Spacer(minLength: 4)
      VStack(alignment: .trailing, spacing: 1) {
        Text(metric?.value.displayText ?? "—")
          .font(.system(size: 18, weight: .semibold, design: .rounded))
          .monospacedDigit()
        Text(
          metric.map { UsagePresentation.caption($0, providerID: state.id) }
            ?? L10n.text("monitor.windowUnavailable", "窗口暂不可用")
        )
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.trailing)
      }
    }
  }

  private var statusContent: some View {
    VStack(alignment: .leading, spacing: 4) {
      if state.status == .stale {
        Label(L10n.text("status.lastData", "上次数据"), systemImage: "clock.arrow.circlepath")
          .foregroundStyle(.orange)
      }
      Text(state.message ?? L10n.text("status.waitingForUsage", "等待用量数据"))
      if let recovery = state.recoverySuggestion { Text(recovery) }
      if let action = state.messageAction { Link(action.title, destination: action.url) }
      if state.id == .codex, state.status == .error {
        Button(L10n.text("monitor.copyLogin", "复制登录命令")) {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString("codex login", forType: .string)
        }.buttonStyle(.link)
      }
    }
    .font(.system(size: 10))
    .foregroundStyle(.secondary)
  }

  private func metricsContent(now: Date) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      ForEach(Array(state.metricGroups.enumerated()), id: \.offset) { _, group in
        VStack(alignment: .leading, spacing: 5) {
          if let name = group.name { Text(name).font(.system(size: 10, weight: .medium)) }
          LazyVGrid(
            columns: group.metrics.count == 1
              ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], spacing: 8
          ) {
            ForEach(group.metrics) { metric in
              VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                  Text(metric.label.replacingOccurrences(of: "Spark · ", with: ""))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                  Spacer(minLength: 3)
                  Text(metric.value.displayText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                if let fraction = metric.value.availableFraction {
                  AvailabilityBar(fraction: fraction)
                    .accessibilityLabel(
                      UsagePresentation.caption(metric, providerID: state.id) + " "
                        + metric.value.displayText)
                }
                if let text = UsagePresentation.resetText(metric, now: now) {
                  Text(text).font(.system(size: 10)).foregroundStyle(.secondary)
                    .help(metric.resetsAt.map(UsagePresentation.fullDate) ?? text)
                }
              }
              .padding(compact ? 7 : 9)
              .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.055)))
            }
          }
        }
      }
    }
  }
}
