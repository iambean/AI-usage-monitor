import Foundation
import SwiftUI

struct CodexCreditBalanceView: View {
  let credits: CodexCreditBalance
  let grant: CodexCreditGrant?
  let now: Date
  var isStale = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 5) {
        Image(systemName: "creditcard")
          .foregroundStyle(Color.accentColor)
          .accessibilityHidden(true)
        Text(L10n.text("codexCredits.title", "Credit 余额"))
          .fontWeight(.medium)
        Spacer(minLength: 4)
        Text(amountText)
          .font(.system(size: 13, weight: .semibold, design: .rounded))
          .monospacedDigit()
          .help(amountHelpText)
      }
      .font(.system(size: 11))
      .accessibilityElement(children: .combine)

      VStack(alignment: .leading, spacing: 4) {
        if let date = credits.expiresAt {
          LabeledContent(L10n.text("codexCredits.expiry", "到期时间")) {
            Text(UsagePresentation.fullDate(date))
          }
        }
        if let grant,
          !grant.isExpired(on: now),
          let expiry = grant.displayExpiry(locale: L10n.locale)
        {
          LabeledContent(
            L10n.format("codexCredits.grantAmount", "获赠 %@ 积分", grant.amount.formatted(.number.locale(L10n.locale)))
          ) {
            Text(L10n.format("codexCredits.grantExpiresOn", "%@到期", expiry))
          }
          .help(L10n.text("codexCredits.grantExpirySource", "来自额度发放邮件"))
        } else if credits.expiresAt == nil {
          LabeledContent(L10n.text("codexCredits.expiryUnknown", "到期时间未提供")) {
            Link(
              L10n.text("codexCredits.openOfficialUsage", "查看官方用量"),
              destination: ProviderUsageDestination.url(for: .codex)
            )
          }
        }
      }
      .font(.system(size: 10))
      .foregroundStyle(.secondary)
    }
    .padding(8)
    .background(
      RoundedRectangle(cornerRadius: 7)
        .fill(Color.accentColor.opacity(0.055))
        .overlay {
          RoundedRectangle(cornerRadius: 7)
            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    )
    .opacity(isStale ? 0.78 : 1)
  }

  private var amountText: String {
    switch credits.amount {
    case .balance(let amount):
      return amount.formatted(
        .number.locale(L10n.locale).precision(.fractionLength(0))
          .rounded(rule: .toNearestOrAwayFromZero))
    case .unlimited:
      return L10n.text("codexCredits.unlimited", "无限")
    case .available:
      return L10n.text("codexCredits.available", "可用")
    case .noneAvailable:
      return L10n.text("codexCredits.noneAvailable", "无可用额度")
    }
  }

  private var amountHelpText: String {
    guard case .balance(let amount) = credits.amount else { return amountText }
    return amount.description
  }

}
