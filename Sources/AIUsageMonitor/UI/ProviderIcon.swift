import AppKit
import ImageIO
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
    ProviderIconImageLoader.image(for: providerID)
  }
}

@MainActor
private enum ProviderIconImageLoader {
  private static let maximumPixelSize = 64
  private static var cache: [ProviderID: NSImage] = [:]

  static func image(for providerID: ProviderID) -> NSImage? {
    if let cached = cache[providerID] {
      return cached
    }
    guard
      let url = Bundle.main.url(
        forResource: "provider-\(providerID.rawValue)",
        withExtension: "png"
      ),
      let source = CGImageSourceCreateWithURL(url as CFURL, nil)
    else {
      return nil
    }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard
      let thumbnail = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        options as CFDictionary
      )
    else {
      return nil
    }
    let image = NSImage(
      cgImage: thumbnail,
      size: NSSize(width: thumbnail.width, height: thumbnail.height)
    )
    cache[providerID] = image
    return image
  }
}
