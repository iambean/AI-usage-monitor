import Foundation

enum CodexResetFeedback: Equatable {
  case success
  case alreadyRedeemed
  case pendingRefresh
  case nothingToReset
  case noCredit
  case uncertain(String? = nil)

  init(outcome: String) {
    switch outcome {
    case "reset": self = .success
    case "alreadyRedeemed": self = .alreadyRedeemed
    case "resetRefreshPending": self = .pendingRefresh
    case "nothingToReset": self = .nothingToReset
    case "noCredit": self = .noCredit
    default: self = .uncertain()
    }
  }

  var title: String {
    switch self {
    case .success: return L10n.text("monitor.resetSuccessTitle", "重置成功")
    case .alreadyRedeemed: return L10n.text("monitor.resetAlreadyTitle", "这次重置已完成")
    case .pendingRefresh: return L10n.text("monitor.resetPendingTitle", "重置已完成，额度待更新")
    case .nothingToReset, .noCredit: return L10n.text("monitor.resetUnusedTitle", "未使用重置次数")
    case .uncertain: return L10n.text("monitor.resetUncertainTitle", "暂未确认重置结果")
    }
  }

  var message: String {
    switch self {
    case .success:
      return L10n.text("monitor.resetSuccessBody", "已使用 1 次重置，额度与剩余次数已更新。")
    case .alreadyRedeemed:
      return L10n.text("monitor.resetAlreadyBody", "此前的请求已成功，本次未重复扣除次数。额度与剩余次数已更新。")
    case .pendingRefresh:
      return L10n.text("monitor.resetPendingRefresh", "重置已确认；额度读取失败，请点击刷新，勿重复使用次数。")
    case .nothingToReset:
      return L10n.text("monitor.nothingToReset", "当前没有可重置的额度，未消耗次数。")
    case .noCredit:
      return L10n.text("monitor.noResetCredit", "当前没有可用重置次数。")
    case .uncertain(let error):
      let guidance = L10n.text("monitor.resetUncertain", "暂未确认重置结果；重试会沿用同一次请求。")
      return error.map { $0 + "\n" + guidance } ?? guidance
    }
  }

  var symbol: String {
    switch self {
    case .success, .alreadyRedeemed: return "checkmark.circle.fill"
    case .pendingRefresh, .uncertain: return "exclamationmark.triangle.fill"
    case .nothingToReset, .noCredit: return "info.circle.fill"
    }
  }
}
