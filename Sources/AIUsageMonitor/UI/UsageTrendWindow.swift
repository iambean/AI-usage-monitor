import AppKit
import Charts
import SwiftUI

private enum UsageTrendRange: String, CaseIterable, Identifiable {
  case day
  case week
  case month

  var id: String { rawValue }

  var title: String {
    switch self {
    case .day:
      return L10n.text("trends.range.24h", "24 小时")
    case .week:
      return L10n.text("trends.range.7d", "7 天")
    case .month:
      return L10n.text("trends.range.30d", "30 天")
    }
  }

  var duration: TimeInterval {
    switch self {
    case .day:
      return 24 * 60 * 60
    case .week:
      return 7 * 24 * 60 * 60
    case .month:
      return 30 * 24 * 60 * 60
    }
  }
}

struct UsageTrendView: View {
  @EnvironmentObject private var model: AppModel
  @State private var selectedProviderID = ProviderID.codex
  @State private var selectedRange = UsageTrendRange.week

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 12) {
        Text(L10n.text("trends.title", "用量趋势"))
          .font(.system(size: 20, weight: .semibold))

        Spacer()

        if !providerIDs.isEmpty {
          Picker(
            L10n.text("trends.provider", "数据源"),
            selection: $selectedProviderID
          ) {
            ForEach(providerIDs, id: \.self) { providerID in
              Text(ProviderCatalog.metadata(for: providerID).name)
                .tag(providerID)
            }
          }
          .labelsHidden()
          .frame(width: 190)

          Picker("", selection: $selectedRange) {
            ForEach(UsageTrendRange.allCases) { range in
              Text(range.title).tag(range)
            }
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 220)
        }
      }

      if providerIDs.isEmpty {
        emptyState(
          symbol: "chart.line.uptrend.xyaxis",
          text: L10n.text(
            "trends.noProviders",
            "启用并成功刷新一个数据源后即可查看趋势"
          )
        )
      } else if visiblePoints.isEmpty {
        emptyState(
          symbol: "clock.arrow.circlepath",
          text: L10n.text(
            "trends.empty",
            "成功刷新后，这里会显示用量变化"
          )
        )
      } else {
        HStack(spacing: 8) {
          ProviderIcon(
            providerID: selectedProviderID,
            fallbackSymbolName: selectedMetadata.symbolName,
            size: 24
          )
          Text(selectedMetadata.name)
            .font(.system(size: 14, weight: .semibold))
          Spacer()
          ForEach(latestPoints) { point in
            VStack(alignment: .trailing, spacing: 1) {
              Text(point.metricLabel)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
              Text(displayText(for: point))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
              RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(0.05))
            )
          }
        }

        trendChart
          .frame(minHeight: 280)
      }

      Text(
        L10n.text(
          "trends.recordingNote",
          "仅保存在本机，最多保留 30 天成功刷新记录"
        )
      )
      .font(.system(size: 10))
      .foregroundStyle(.tertiary)
    }
    .padding(24)
    .frame(minWidth: 680, minHeight: 440)
    .onAppear(perform: synchronizeSelection)
    .onChange(of: providerIDs) { _ in
      synchronizeSelection()
    }
  }

  @ViewBuilder
  private var trendChart: some View {
    if visiblePoints.first?.scale == .percent {
      chart
        .chartYScale(domain: 0...100)
    } else {
      chart
    }
  }

  private var chart: some View {
    Chart(visiblePoints) { point in
      LineMark(
        x: .value("Time", point.recordedAt),
        y: .value(L10n.text("trends.value", "用量"), point.value)
      )
      .foregroundStyle(by: .value("Metric", point.metricLabel))
      .interpolationMethod(.linear)

      if seriesCounts[point.seriesID] == 1 {
        PointMark(
          x: .value("Time", point.recordedAt),
          y: .value(L10n.text("trends.value", "用量"), point.value)
        )
        .foregroundStyle(by: .value("Metric", point.metricLabel))
      }
    }
    .chartLegend(position: .top, alignment: .leading, spacing: 12)
  }

  private var providerIDs: [ProviderID] {
    model.trendProviderIDs
  }

  private var selectedMetadata: ProviderMetadata {
    ProviderCatalog.metadata(for: selectedProviderID)
  }

  private var visiblePoints: [UsageHistoryPoint] {
    let cutoff = Date().addingTimeInterval(-selectedRange.duration)
    let points = model.usageHistory.filter {
      $0.providerID == selectedProviderID && $0.recordedAt >= cutoff
    }
    guard !points.isEmpty else { return [] }

    let preferredScale: UsageHistoryScale
    if points.contains(where: { $0.scale == .percent }) {
      preferredScale = .percent
    } else if points.contains(where: { $0.scale == .currency }) {
      preferredScale = .currency
    } else {
      preferredScale = .quantity
    }
    let preferredUnit = points.first(where: { $0.scale == preferredScale })?.unit
    return points
      .filter { $0.scale == preferredScale && $0.unit == preferredUnit }
      .sorted { $0.recordedAt < $1.recordedAt }
  }

  private var seriesCounts: [String: Int] {
    Dictionary(grouping: visiblePoints, by: \.seriesID)
      .mapValues(\.count)
  }

  private var latestPoints: [UsageHistoryPoint] {
    Dictionary(grouping: visiblePoints, by: \.seriesID)
      .compactMap { $0.value.max(by: { $0.recordedAt < $1.recordedAt }) }
      .sorted { $0.metricLabel < $1.metricLabel }
  }

  private func displayText(for point: UsageHistoryPoint) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = point.scale == .currency ? 2 : 1
    formatter.minimumFractionDigits = point.scale == .currency ? 2 : 0
    let number = formatter.string(from: NSNumber(value: point.value)) ?? "\(point.value)"
    switch point.scale {
    case .percent:
      return "\(number)%"
    case .currency:
      switch point.unit?.uppercased() {
      case "CNY":
        return "¥\(number)"
      case "USD":
        return "$\(number)"
      default:
        return [point.unit, number].compactMap { $0 }.joined(separator: " ")
      }
    case .quantity:
      return [number, point.unit].compactMap { $0 }.joined(separator: " ")
    }
  }

  private func synchronizeSelection() {
    guard let firstProviderID = providerIDs.first else { return }
    if !providerIDs.contains(selectedProviderID) {
      selectedProviderID = firstProviderID
    }
  }

  private func emptyState(symbol: String, text: String) -> some View {
    VStack(spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 28))
        .foregroundStyle(.tertiary)
      Text(text)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .frame(minHeight: 300)
  }
}

@MainActor
final class UsageTrendWindowController: NSWindowController, NSWindowDelegate {
  static let shared = UsageTrendWindowController()

  func show(model: AppModel) {
    let preferredScreen = NSApp.keyWindow?.screen ?? screenContainingMouse
    let trendWindow = window ?? makeWindow(model: model, screen: preferredScreen)
    WindowPresentationPolicy.natural.apply(to: trendWindow)
    showWindow(nil)
    trendWindow.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func makeWindow(model: AppModel, screen: NSScreen?) -> NSWindow {
    let rootView = AnyView(
      UsageTrendView()
        .environmentObject(model)
    )
    let trendWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 700, height: 470),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    trendWindow.title = L10n.text("trends.title", "用量趋势")
    trendWindow.contentViewController = NSHostingController(rootView: rootView)
    trendWindow.delegate = self
    trendWindow.isReleasedWhenClosed = false
    trendWindow.minSize = NSSize(width: 680, height: 440)
    center(trendWindow, on: screen)

    window = trendWindow
    return trendWindow
  }

  private var screenContainingMouse: NSScreen? {
    let mouseLocation = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
      ?? NSScreen.main
  }

  private func center(_ window: NSWindow, on screen: NSScreen?) {
    guard let screen else {
      window.center()
      return
    }
    let visibleFrame = screen.visibleFrame
    window.setFrameOrigin(
      NSPoint(
        x: visibleFrame.midX - window.frame.width / 2,
        y: visibleFrame.midY - window.frame.height / 2
      )
    )
  }

  func windowWillClose(_ notification: Notification) {
    guard notification.object as? NSWindow === window else { return }
    window = nil
  }
}
