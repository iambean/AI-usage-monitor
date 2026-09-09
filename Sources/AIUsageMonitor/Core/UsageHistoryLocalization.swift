import Foundation

// History keeps the original label for export. Translate known labels only in the
// chart snapshot, once per distinct label, without changing sample or series IDs.
struct UsageHistoryLocalization {
  private let language: AppLanguage
  private let english: Bool
  private let labels: [String: String]

  init(language: AppLanguage) {
    self.language = language
    english = language.locale.languageCode != "zh"
    let entries = [
      ("usage.cycle", "周期", "Cycle"),
      ("usage.week", "周", "Week"),
      ("usage.fiveHours", "5 小时", "5 hours"),
      ("usage.monthly", "月度", "Monthly"),
      ("usage.shortTerm", "短期", "Short term"),
      ("usage.totalQuota", "总额度", "Total quota"),
      ("usage.planQuota", "套餐额度", "Plan quota"),
      ("usage.resourcePackage", "资源包", "Resource package"),
      ("usage.teamShared", "团队共享", "Team shared"),
      ("usage.teamSpend", "本周期团队支出", "Team spend this cycle"),
      ("usage.teamMembers", "团队成员", "Team members"),
      ("usage.apiBalance", "API 可用余额", "Available API balance"),
    ]
    var labels: [String: String] = [:]
    for (key, chinese, englishText) in entries {
      let target = L10n.localizedString(
        key, fallback: english ? englishText : chinese, language: language)
      labels[chinese] = target
      labels[englishText] = target
    }
    self.labels = labels
  }

  func label(_ original: String) -> String {
    original.components(separatedBy: " · ").map { part in
      if let translated = labels[part] { return translated }
      for (chinese, englishUnit, key) in [
        ("分钟", "minutes", "usage.minutes"),
        ("小时", "hours", "usage.hours"),
        ("天", "days", "usage.days"),
      ] {
        for suffix in [" " + chinese, " " + englishUnit] where part.hasSuffix(suffix) {
          if let count = Int(part.dropLast(suffix.count)) {
            let template = L10n.localizedString(
              key, fallback: "%d " + (english ? englishUnit : chinese), language: language)
            return String(format: template, locale: language.locale, count)
          }
        }
      }
      for suffix in [" 可用余额", " available balance"] where part.hasSuffix(suffix) {
        let currency = String(part.dropLast(suffix.count))
        let template = L10n.localizedString(
          "usage.availableBalance", fallback: english ? "%@ available balance" : "%@ 可用余额",
          language: language)
        return String(format: template, locale: language.locale, currency)
      }
      return part
    }.joined(separator: " · ")
  }
}
