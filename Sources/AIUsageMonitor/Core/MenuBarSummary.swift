enum MenuBarSummary {
  static func displayText(for state: ProviderUsageState) -> String {
    state.defaultSummary?.compactDisplayText ?? "—"
  }

  static func displayText(for states: [ProviderUsageState]) -> String {
    states.first.map(displayText(for:)) ?? "—"
  }
}
