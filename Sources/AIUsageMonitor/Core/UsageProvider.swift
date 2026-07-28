import Foundation

protocol UsageProvider: Actor {
  nonisolated var metadata: ProviderMetadata { get }

  func updates() -> AsyncStream<ProviderUsageState>
  func start() async
  func refresh() async
  func setRefreshRole(_ role: ProviderRefreshRole) async
  func stop() async
}
