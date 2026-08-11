import Foundation

enum UsageResetFormatter {
  static func dateTime(
    for date: Date,
    locale: Locale = L10n.locale,
    timeZone: TimeZone = .current
  ) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.setLocalizedDateFormatFromTemplate("MMMdjm")
    return formatter.string(from: date)
  }
}
