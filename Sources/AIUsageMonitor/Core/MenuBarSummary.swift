enum MenuBarSummary {
  static func displayText(for states: [ProviderUsageState]) -> String {
    states.first?.defaultSummary?.compactDisplayText ?? "—"
  }
}
