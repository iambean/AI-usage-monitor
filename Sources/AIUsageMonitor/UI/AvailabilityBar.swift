import SwiftUI

struct AvailabilityBar: View {
  let fraction: Double

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.primary.opacity(0.12))
        Capsule()
          .fill(Color.primary.opacity(0.78))
          .frame(
            width: proxy.size.width * CGFloat(fraction.clamped(to: 0...1))
          )
      }
    }
    .frame(height: 5)
    .accessibilityLabel("剩余 \(Int((fraction * 100).rounded()))%")
  }
}

extension Comparable {
  fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
