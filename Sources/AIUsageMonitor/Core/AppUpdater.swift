import Sparkle

@MainActor
final class AppUpdater {
  private let controller: SPUStandardUpdaterController

  init() {
    controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
  }

  func installAvailableUpdate() {
    controller.checkForUpdates(nil)
  }
}
