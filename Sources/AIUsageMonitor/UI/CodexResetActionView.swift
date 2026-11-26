import SwiftUI

struct CodexResetActionView: View {
  var canReset: Bool
  var isInProgress: Bool
  var feedback: CodexResetFeedback?
  @Binding var confirmationRequested: Bool
  var onReset: () -> Void
  var onDismissFeedback: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if isInProgress {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text(L10n.text("monitor.resetting", "正在重置并重新查询额度…"))
        }
        .accessibilityElement(children: .combine)
      } else if canReset {
        if confirmationRequested {
          VStack(alignment: .leading, spacing: 8) {
            Label(
              L10n.text("monitor.confirmResetTitle", "使用一次重置？"), systemImage: "questionmark.circle"
            )
            .font(.system(size: 11, weight: .semibold))
            Text(L10n.text("monitor.confirmResetBody", "这将消耗 1 次可用重置。完成后重新查询额度与剩余次数。"))
              .fixedSize(horizontal: false, vertical: true)
            HStack {
              Spacer()
              Button(L10n.text("common.cancel", "取消"), action: cancel)
                .buttonStyle(.bordered)
              Button(L10n.text("monitor.confirmReset", "确认使用"), action: confirm)
                .buttonStyle(.borderedProminent)
            }
          }
          .padding(10)
          .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
        } else {
          Button(L10n.text("monitor.useReset", "使用一次重置…"), action: requestConfirmation)
            .buttonStyle(.link)
        }
      }
      if !isInProgress, let feedback {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: feedback.symbol).foregroundStyle(feedbackColor(feedback))
          VStack(alignment: .leading, spacing: 4) {
            Text(feedback.title).fontWeight(.semibold)
            Text(feedback.message).fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 0)
          Button(action: onDismissFeedback) { Image(systemName: "xmark") }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("monitor.dismissResetFeedback", "关闭重置结果"))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(feedbackColor(feedback).opacity(0.1)))
      }
    }
    .font(.system(size: 10))
    .onChange(of: canReset) { allowed in
      if !allowed { confirmationRequested = false }
    }
    .onChange(of: isInProgress) { running in
      if running { confirmationRequested = false }
    }
  }

  func requestConfirmation() {
    guard canReset, !isInProgress else { return }
    confirmationRequested = true
  }

  func cancel() {
    confirmationRequested = false
  }

  func confirm() {
    // Re-check the binding so a repeated click cannot confirm twice.
    guard confirmationRequested, canReset, !isInProgress else { return }
    confirmationRequested = false
    onReset()
  }

  private func feedbackColor(_ feedback: CodexResetFeedback) -> Color {
    switch feedback {
    case .success, .alreadyRedeemed: return .green
    case .pendingRefresh, .uncertain: return .orange
    case .nothingToReset, .noCredit: return .secondary
    }
  }
}
