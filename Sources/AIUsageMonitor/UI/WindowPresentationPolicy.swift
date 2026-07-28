import AppKit

enum WindowPresentationPolicy {
  case natural

  @MainActor
  func apply(to window: NSWindow) {
    window.level = .normal
    window.hidesOnDeactivate = false
    window.collectionBehavior.remove(.canJoinAllSpaces)
    window.collectionBehavior.remove(.fullScreenAuxiliary)
  }
}
