import AppKit

enum WindowPresentationPolicy {
  case natural
  case menuPanel

  @MainActor
  func apply(to window: NSWindow) {
    window.level = .normal
    // Explicit orderOut on focus/app/Space changes prevents automatic restoration.
    // AppKit's implicit hiding can suppress a panel opened from the status item.
    window.hidesOnDeactivate = false
    window.collectionBehavior.remove(.canJoinAllSpaces)
    window.collectionBehavior.remove(.fullScreenAuxiliary)
  }
}
