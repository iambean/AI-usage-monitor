import SwiftUI

struct AvailabilityBar: View {
  let fraction: Double

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.primary.opacity(0.12))
        Capsule()
          .fill(availabilityColor)
          .frame(
            width: proxy.size.width * CGFloat(fraction.clamped(to: 0...1))
          )
      }
    }
    .frame(height: 5)
    .accessibilityLabel(
      L10n.format(
        "usage.remainingPercent",
        "剩余 %d%%",
        Int((fraction * 100).rounded())
      )
    )
  }

  private var availabilityColor: Color {
    Color(
      hue: AvailabilityColorScale.hue(for: fraction),
      saturation: 0.82,
      brightness: 0.86
    )
  }
}

enum AvailabilityColorScale {
  static func hue(for fraction: Double) -> Double {
    fraction.clamped(to: 0...1) / 3
  }
}

extension Comparable {
  fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
