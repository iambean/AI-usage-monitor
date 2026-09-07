import SwiftUI

struct CodexResetCreditsView: View {
  let credits: CodexResetCredits?
  var isStale = false
  @Binding var isExpanded: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let credits, credits.availableCount > 0 {
        Button {
          isExpanded.toggle()
        } label: {
          header
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(
          isExpanded
            ? L10n.text("resetCredits.expanded", "已展开")
            : L10n.text("resetCredits.collapsed", "已折叠")
        )

        if isExpanded {
          Divider()
          details(credits)
            .padding(8)
        }
      } else {
        header
      }
    }
    .background(
      RoundedRectangle(cornerRadius: 7)
        .fill(Color.accentColor.opacity(0.055))
        .overlay {
          RoundedRectangle(cornerRadius: 7)
            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    )
  }

  private var header: some View {
    HStack(spacing: 5) {
      Image(systemName: "ticket")
        .foregroundStyle(Color.accentColor)
        .accessibilityHidden(true)
      Text(countText)
        .fontWeight(.medium)
        .fixedSize(horizontal: true, vertical: false)
      Spacer(minLength: 4)
      Text(expirySummary)
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.trailing)
      if let credits, credits.availableCount > 0 {
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
          .font(.system(size: 8, weight: .medium))
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
    }
    .font(.system(size: 10))
    .padding(8)
  }

  private var countText: String {
    guard let credits else {
      return L10n.text("resetCredits.unavailableCount", "可用重置 —")
    }
    if isStale {
      return L10n.format("resetCredits.lastCount", "上次可用重置 %d 次", credits.availableCount)
    }
    return L10n.format("resetCredits.count", "可用重置 %d 次", credits.availableCount)
  }

  private var expirySummary: String {
    guard let credits else {
      return L10n.text("resetCredits.unavailable", "暂未获取")
    }
    guard credits.availableCount > 0 else { return "" }
    guard let expiry = credits.earliestKnownExpiry else {
      return L10n.text("resetCredits.unknownExpiry", "有效期未知")
    }
    if expiry <= Date() {
      return L10n.text("resetCredits.awaitingUpdate", "到期信息待更新")
    }
    let formatter = DateFormatter()
    formatter.locale = L10n.locale
    formatter.setLocalizedDateFormatFromTemplate("MMMd")
    let date = formatter.string(from: expiry)
    return credits.hasCompleteExpiryDetails
      ? L10n.format("resetCredits.nextExpiry", "最近到期 %@", date)
      : L10n.format("resetCredits.knownExpiry", "已知最早到期 %@", date)
  }

  private func details(_ credits: CodexResetCredits) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(L10n.text("resetCredits.availableUses", "可用次数"))
        Spacer()
        Text(L10n.format("resetCredits.expiryTimeZone", "到期时间 · %@", timeZoneLabel))
      }
      .font(.system(size: 9))
      .foregroundStyle(.secondary)

      ForEach(Array(credits.sortedCredits.enumerated()), id: \.offset) { _, credit in
        HStack(alignment: .firstTextBaseline) {
          Text(L10n.text("resetCredits.oneUse", "1 次"))
          Spacer(minLength: 8)
          Text(credit.expiresAt.map(fullDate) ?? L10n.text("resetCredits.unknownExpiry", "有效期未知"))
            .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 10))
        .monospacedDigit()
      }

      if credits.sortedCredits.isEmpty {
        Text(L10n.text("resetCredits.noDetails", "暂未获取有效期明细"))
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      } else if credits.sortedCredits.count < credits.availableCount {
        Text(
          L10n.format(
            "resetCredits.partialDetails", "已返回 %d / %d 条明细",
            credits.sortedCredits.count, credits.availableCount
          )
        )
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
      }

      Text(L10n.text("resetCredits.note", "手动重置次数，与额度自动重置时间分开。"))
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
      Text(L10n.format("resetCredits.updatedAt", "更新于 %@", fullDate(credits.updatedAt)))
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
    }
  }

  private var timeZoneLabel: String {
    TimeZone.current.localizedName(for: .standard, locale: L10n.locale)
      ?? TimeZone.current.identifier
  }

  private func fullDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = L10n.locale
    formatter.setLocalizedDateFormatFromTemplate("yMMMdjm")
    return formatter.string(from: date)
  }
}
