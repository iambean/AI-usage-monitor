import AppKit
import Combine

struct MenuPanelGeometry {
  let anchor: NSRect
  let visibleFrame: NSRect
  static let width: CGFloat = 350
  private let margin: CGFloat = 8
  private let gap: CGFloat = 6

  var top: CGFloat { min(anchor.minY, visibleFrame.maxY) - gap }
  var maximumHeight: CGFloat { max(1, top - visibleFrame.minY - margin) }

  func frame(contentHeight: CGFloat) -> NSRect {
    let height = min(max(1, contentHeight), maximumHeight)
    let x = min(
      max(anchor.maxX - Self.width, visibleFrame.minX + margin),
      visibleFrame.maxX - Self.width - margin)
    return NSRect(x: x, y: top - height, width: Self.width, height: height)
  }
}

@MainActor
final class MenuPanelSizing: ObservableObject {
  @Published var maximumHeight: CGFloat = .infinity
}
