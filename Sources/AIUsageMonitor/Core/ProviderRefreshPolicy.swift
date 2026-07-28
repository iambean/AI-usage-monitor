import Foundation

enum ProviderRefreshRole: Sendable, Equatable {
  case primary
  case secondary
  case lowPowerPrimary
  case suspended
}

enum ProviderRefreshPolicy {
  static let secondaryInterval: TimeInterval = 3_600

  static func interval(
    baseInterval: TimeInterval,
    role: ProviderRefreshRole
  ) -> TimeInterval? {
    switch role {
    case .primary:
      return baseInterval
    case .secondary:
      return max(baseInterval, secondaryInterval)
    case .lowPowerPrimary:
      return baseInterval * 2
    case .suspended:
      return nil
    }
  }

  static func failureDelay(
    baseInterval: TimeInterval,
    role: ProviderRefreshRole,
    consecutiveFailures: Int
  ) -> TimeInterval? {
    guard let scheduledInterval = interval(baseInterval: baseInterval, role: role) else {
      return nil
    }
    guard consecutiveFailures > 0 else { return scheduledInterval }

    let backoff: [TimeInterval] = [60, 120, 300, 900, 1_800, 3_600]
    let backoffInterval = backoff[min(consecutiveFailures - 1, backoff.count - 1)]
    return max(scheduledInterval, backoffInterval)
  }
}
