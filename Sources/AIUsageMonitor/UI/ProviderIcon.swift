import AppKit
import SwiftUI

struct ProviderIcon: View {
  let providerID: ProviderID
  let fallbackSymbolName: String
  let size: CGFloat

  var body: some View {
    Group {
      if let image = providerImage {
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
          .scaledToFit()
      } else {
        Image(systemName: fallbackSymbolName)
          .resizable()
          .scaledToFit()
          .symbolRenderingMode(.monochrome)
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  private var providerImage: NSImage? {
    guard
      let url = Bundle.main.url(
        forResource: "provider-\(providerID.rawValue)",
        withExtension: "png"
      )
    else {
      return nil
    }
    return NSImage(contentsOf: url)
  }
}
