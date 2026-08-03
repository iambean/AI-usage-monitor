import SwiftUI

struct ProviderUsageRow: View {
  let state: ProviderUsageState

  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      Link(destination: ProviderUsageDestination.url(for: state.id)) {
        header
      }
      .buttonStyle(.plain)
      .help(
        L10n.format(
          "usage.openProviderPage",
          "打开 %@ 用量页面",
          state.name
        )
      )

      if !canShowUsage || state.metrics.isEmpty {
        VStack(alignment: .leading, spacing: 5) {
          statusMessage
          if let recoverySuggestion = state.recoverySuggestion {
            Text(recoverySuggestion)
              .foregroundStyle(.tertiary)
          }
        }
        .font(.system(size: 10))
        .padding(.leading, 34)
      } else {
        LazyVGrid(
          columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
          ],
          alignment: .leading,
          spacing: 8
        ) {
          ForEach(state.displayMetrics) { metric in
            VStack(alignment: .leading, spacing: 3) {
              Text(metric.label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)

              Text(metric.value.displayText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

              if let resetText = resetText(metric) {
                Text(resetText)
                  .font(.system(size: 9))
                  .foregroundStyle(.tertiary)
                  .lineLimit(1)
                  .minimumScaleFactor(0.75)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(
              RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(0.045))
            )
          }
        }
        .padding(.leading, 34)
      }

      if let fraction = visibleSummary?.availableFraction {
        AvailabilityBar(fraction: fraction)
      }
    }
    .padding(.vertical, 5)
  }

  private var statusMessage: Text {
    var content = AttributedString(
      state.message ?? L10n.text("status.waitingForUsage", "等待用量数据")
    )
    content.foregroundColor = Color(nsColor: .secondaryLabelColor)

    if let action = state.messageAction {
      var link = AttributedString(action.title)
      link.link = action.url
      link.foregroundColor = .accentColor
      content.append(link)
    }

    return Text(content)
  }

  private var header: some View {
    HStack(spacing: 10) {
      ProviderIcon(
        providerID: state.id,
        fallbackSymbolName: state.symbolName,
        size: 25
      )
      .frame(width: 24)

      Text(state.name)
        .font(.system(size: 14, weight: .semibold))

      Spacer(minLength: 12)

      VStack(alignment: .trailing, spacing: 1) {
        Text(visibleSummary?.displayText ?? "—")
          .font(.system(size: 18, weight: .semibold, design: .rounded))
          .monospacedDigit()
        Text(summaryCaption)
          .font(.system(size: 9))
          .foregroundStyle(.tertiary)
      }
    }
    .frame(maxWidth: .infinity)
    .contentShape(Rectangle())
  }

  private var statusCaption: String {
    switch state.status {
    case .loading:
      return L10n.text("status.connecting", "连接中")
    case .needsConfiguration:
      return L10n.text("status.needsConfiguration", "待配置")
    case .stale:
      return L10n.text("status.lastData", "上次数据")
    case .error:
      return L10n.text("status.unavailable", "不可用")
    case .connected:
      return L10n.text("status.usage", "用量")
    }
  }

  private var summaryCaption: String {
    visibleSummary == nil
      ? statusCaption
      : state.status == .connected
        ? visibleSummary?.caption ?? statusCaption
        : statusCaption
  }

  private var visibleSummary: UsageValue? {
    canShowUsage ? state.defaultSummary : nil
  }

  private var canShowUsage: Bool {
    state.status == .connected || state.status == .stale
  }

  private func resetText(_ metric: UsageMetric) -> String? {
    if let description = metric.resetDescription {
      return description
    }
    guard let date = metric.resetsAt else { return nil }
    return L10n.format(
      "usage.resetsAt",
      "%@重置",
      UsageResetFormatter.dateTime(for: date)
    )
  }
}
