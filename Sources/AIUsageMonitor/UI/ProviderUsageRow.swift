import SwiftUI

struct ProviderUsageRow: View {
  let state: ProviderUsageState

  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
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
          Text(state.summary?.displayText ?? "—")
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .monospacedDigit()
          Text(state.summary?.caption ?? statusCaption)
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
        }
      }

      if state.metrics.isEmpty {
        Text(state.message ?? "等待用量数据")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .padding(.leading, 34)
      } else {
        VStack(spacing: 7) {
          ForEach(state.metrics) { metric in
            HStack(alignment: .firstTextBaseline) {
              VStack(alignment: .leading, spacing: 1) {
                Text(metric.label)
                  .foregroundStyle(.secondary)
                if let resetText = resetText(metric) {
                  Text(resetText)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                }
              }
              Spacer()
              Text(metric.value.displayText)
                .foregroundStyle(.primary)
                .monospacedDigit()
            }
            .font(.system(size: 11))
          }
        }
        .padding(.leading, 34)
      }

      if let fraction = state.summary?.availableFraction {
        AvailabilityBar(fraction: fraction)
      }
    }
    .padding(.vertical, 5)
  }

  private var statusCaption: String {
    switch state.status {
    case .loading:
      return "连接中"
    case .needsConfiguration:
      return "待配置"
    case .stale:
      return "上次数据"
    case .error:
      return "不可用"
    case .connected:
      return "用量"
    }
  }

  private func resetText(_ metric: UsageMetric) -> String? {
    if let description = metric.resetDescription {
      return description
    }
    guard let date = metric.resetsAt else { return nil }
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date()) + "重置"
  }
}
