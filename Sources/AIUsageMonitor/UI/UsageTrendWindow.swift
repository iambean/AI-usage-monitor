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
  @State private var chartData = UsageTrendChartData.empty
  @State private var hoverState = UsageTrendHoverState()

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
      } else if chartData.points.isEmpty {
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
    .onAppear(perform: rebuildChartData)
    .onChange(of: providerIDs) { _ in
      synchronizeSelection()
    }
    .onChange(of: selectedProviderID) { _ in
      hoverState.clear()
      rebuildChartData()
    }
    .onChange(of: selectedRange) { _ in
      hoverState.clear()
      rebuildChartData()
    }
    .onChange(of: model.usageHistory) { _ in
      rebuildChartData()
    }
  }

  @ViewBuilder
  private var trendChart: some View {
    ZStack {
      if chartData.points.first?.scale == .percent {
        chart
          .chartYScale(domain: 0...100)
      } else {
        chart
      }
      UsageTrendHoverOverlay(state: hoverState)
    }
  }

  private var chart: some View {
    Chart {
      ForEach(chartData.points) { point in
        LineMark(
          x: .value("Time", point.recordedAt),
          y: .value(L10n.text("trends.value", "用量"), point.value)
        )
        .foregroundStyle(by: .value("Metric", point.metricLabel))
        .interpolationMethod(.linear)

        if chartData.seriesCounts[point.seriesID] == 1 {
          PointMark(
            x: .value("Time", point.recordedAt),
            y: .value(L10n.text("trends.value", "用量"), point.value)
          )
          .foregroundStyle(by: .value("Metric", point.metricLabel))
        }
      }

    }
    .chartLegend(position: .top, alignment: .leading, spacing: 12)
    .chartOverlay { proxy in
      GeometryReader { geometry in
        Rectangle()
          .fill(Color.clear)
          .contentShape(Rectangle())
          .onContinuousHover { phase in
            updateHoverSelection(
              phase: phase,
              proxy: proxy,
              geometry: geometry
            )
          }
      }
    }
  }

  private var providerIDs: [ProviderID] {
    model.trendProviderIDs
  }

  private var selectedMetadata: ProviderMetadata {
    ProviderCatalog.metadata(for: selectedProviderID)
  }

  private func makeChartData(now: Date = Date()) -> UsageTrendChartData {
    let cutoff = now.addingTimeInterval(-selectedRange.duration)
    let points = model.usageHistory.filter {
      $0.providerID == selectedProviderID && $0.recordedAt >= cutoff
    }
    guard !points.isEmpty else { return .empty }

    let preferredScale: UsageHistoryScale
    if points.contains(where: { $0.scale == .percent }) {
      preferredScale = .percent
    } else if points.contains(where: { $0.scale == .currency }) {
      preferredScale = .currency
    } else {
      preferredScale = .quantity
    }
    let preferredUnit = points.first(where: { $0.scale == preferredScale })?.unit
    let visiblePoints = points
      .filter { $0.scale == preferredScale && $0.unit == preferredUnit }
      .sorted { $0.recordedAt < $1.recordedAt }
    return UsageTrendChartData(points: visiblePoints)
  }

  private var latestPoints: [UsageHistoryPoint] {
    chartData.latestPoints
  }

  private func displayText(for point: UsageHistoryPoint) -> String {
    UsageTrendFormatting.displayText(for: point)
  }

  private func synchronizeSelection() {
    guard let firstProviderID = providerIDs.first else { return }
    if !providerIDs.contains(selectedProviderID) {
      selectedProviderID = firstProviderID
    }
  }

  private func rebuildChartData() {
    chartData = makeChartData()
  }

  private func updateHoverSelection(
    phase: HoverPhase,
    proxy: ChartProxy,
    geometry: GeometryProxy
  ) {
    switch phase {
    case .active(let location):
      let plotFrame = geometry[proxy.plotAreaFrame]
      guard plotFrame.contains(location) else {
        hoverState.clear()
        return
      }
      let xPosition = location.x - plotFrame.origin.x
      guard let date: Date = proxy.value(atX: xPosition) else {
        hoverState.clear()
        return
      }
      guard
        let timestamp = chartData.nearestTimestamp(to: date),
        let snappedX = proxy.position(forX: timestamp)
      else { return }
      hoverState.update(
        UsageTrendHoverSelection(
          timestamp: timestamp,
          points: chartData.values(at: timestamp),
          x: plotFrame.minX + snappedX,
          plotFrame: plotFrame
        )
      )
    case .ended:
      hoverState.clear()
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

private struct UsageTrendHoverSelection: Equatable {
  let timestamp: Date
  let points: [UsageHistoryPoint]
  let x: CGFloat
  let plotFrame: CGRect
}

@MainActor
private final class UsageTrendHoverState: ObservableObject {
  @Published private(set) var selection: UsageTrendHoverSelection?

  func update(_ selection: UsageTrendHoverSelection) {
    guard self.selection != selection else { return }
    self.selection = selection
  }

  func clear() {
    guard selection != nil else { return }
    selection = nil
  }
}

private struct UsageTrendHoverOverlay: View {
  @ObservedObject var state: UsageTrendHoverState

  var body: some View {
    GeometryReader { geometry in
      if let selection = state.selection {
        Path { path in
          path.move(to: CGPoint(x: selection.x, y: selection.plotFrame.minY))
          path.addLine(to: CGPoint(x: selection.x, y: selection.plotFrame.maxY))
        }
        .stroke(
          Color.secondary.opacity(0.8),
          style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [4, 4])
        )

        tooltip(for: selection)
          .frame(width: 160)
          .position(
            x: tooltipCenterX(selection: selection, width: geometry.size.width),
            y: selection.plotFrame.minY + 58
          )
      }
    }
    .allowsHitTesting(false)
  }

  private func tooltip(for selection: UsageTrendHoverSelection) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(UsageTrendFormatting.dateText(selection.timestamp))
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.primary)
        .monospacedDigit()

      ForEach(selection.points) { point in
        HStack(spacing: 12) {
          Text(point.metricLabel)
            .foregroundStyle(.secondary)
          Spacer(minLength: 8)
          Text(UsageTrendFormatting.displayText(for: point))
            .fontWeight(.semibold)
            .monospacedDigit()
        }
        .font(.system(size: 10))
      }
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 7)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
    )
    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
  }

  private func tooltipCenterX(
    selection: UsageTrendHoverSelection,
    width: CGFloat
  ) -> CGFloat {
    let halfWidth: CGFloat = 80
    let preferred = selection.x < selection.plotFrame.midX
      ? selection.x + halfWidth + 8
      : selection.x - halfWidth - 8
    return min(max(preferred, halfWidth), width - halfWidth)
  }
}

@MainActor
private enum UsageTrendFormatting {
  private static var numberFormatters: [String: NumberFormatter] = [:]
  private static var dateFormatters: [String: DateFormatter] = [:]

  static func displayText(for point: UsageHistoryPoint) -> String {
    let maximumFractionDigits = point.scale == .currency ? 2 : 1
    let minimumFractionDigits = point.scale == .currency ? 2 : 0
    let locale = L10n.locale
    let key = "\(locale.identifier):\(minimumFractionDigits):\(maximumFractionDigits)"
    let formatter: NumberFormatter
    if let cachedFormatter = numberFormatters[key] {
      formatter = cachedFormatter
    } else {
      let newFormatter = NumberFormatter()
      newFormatter.locale = locale
      newFormatter.numberStyle = .decimal
      newFormatter.maximumFractionDigits = maximumFractionDigits
      newFormatter.minimumFractionDigits = minimumFractionDigits
      numberFormatters[key] = newFormatter
      formatter = newFormatter
    }
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

  static func dateText(_ date: Date) -> String {
    let locale = L10n.locale
    let timeZone = TimeZone.current
    let key = "\(locale.identifier):\(timeZone.identifier)"
    let formatter: DateFormatter
    if let cachedFormatter = dateFormatters[key] {
      formatter = cachedFormatter
    } else {
      let newFormatter = DateFormatter()
      newFormatter.locale = locale
      newFormatter.timeZone = timeZone
      newFormatter.dateStyle = .medium
      newFormatter.timeStyle = .short
      dateFormatters[key] = newFormatter
      formatter = newFormatter
    }
    return formatter.string(from: date)
  }
}

struct UsageTrendChartData: Equatable {
  static let empty = UsageTrendChartData(points: [])

  let points: [UsageHistoryPoint]
  let seriesCounts: [String: Int]
  let latestPoints: [UsageHistoryPoint]
  private let timestamps: [Date]
  private let series: [[UsageHistoryPoint]]

  init(points: [UsageHistoryPoint]) {
    let orderedPoints = points.sorted { $0.recordedAt < $1.recordedAt }
    self.points = orderedPoints
    let groupedPoints = Dictionary(grouping: orderedPoints, by: \.seriesID)
    seriesCounts = groupedPoints.mapValues(\.count)
    let groupedSeries = Array(groupedPoints.values)
    series = groupedSeries
    latestPoints = groupedSeries
      .compactMap(\.last)
      .sorted { $0.metricLabel < $1.metricLabel }
    timestamps = Array(Set(orderedPoints.map(\.recordedAt))).sorted()
  }

  func nearestTimestamp(to target: Date) -> Date? {
    UsageTrendSelection.nearestTimestamp(to: target, in: timestamps)
  }

  func values(at timestamp: Date?) -> [UsageHistoryPoint] {
    guard let timestamp else { return [] }
    return UsageTrendSelection.values(at: timestamp, in: series)
  }
}

enum UsageTrendSelection {
  static func nearestTimestamp(
    to target: Date,
    in timestamps: [Date]
  ) -> Date? {
    guard !timestamps.isEmpty else { return nil }

    var lowerBound = 0
    var upperBound = timestamps.count
    while lowerBound < upperBound {
      let middle = (lowerBound + upperBound) / 2
      if timestamps[middle] < target {
        lowerBound = middle + 1
      } else {
        upperBound = middle
      }
    }

    if lowerBound == 0 { return timestamps[0] }
    if lowerBound == timestamps.count { return timestamps[timestamps.count - 1] }
    let previous = timestamps[lowerBound - 1]
    let next = timestamps[lowerBound]
    return target.timeIntervalSince(previous) <= next.timeIntervalSince(target)
      ? previous
      : next
  }

  static func values(
    at timestamp: Date,
    in series: [[UsageHistoryPoint]]
  ) -> [UsageHistoryPoint] {
    series
      .compactMap { ordered in
        guard !ordered.isEmpty else { return nil }
        var lowerBound = 0
        var upperBound = ordered.count
        while lowerBound < upperBound {
          let middle = (lowerBound + upperBound) / 2
          if ordered[middle].recordedAt <= timestamp {
            lowerBound = middle + 1
          } else {
            upperBound = middle
          }
        }
        return lowerBound == 0 ? ordered.first : ordered[lowerBound - 1]
      }
      .sorted { $0.metricLabel < $1.metricLabel }
  }
}

@MainActor
final class UsageTrendWindowController: NSWindowController, NSWindowDelegate {
  static let shared = UsageTrendWindowController()

  func show(model: AppModel) {
    let preferredScreen = NSApp.keyWindow?.screen ?? screenContainingMouse
    let trendWindow = window ?? makeWindow(model: model, screen: preferredScreen)
    updateLocalization()
    WindowPresentationPolicy.natural.apply(to: trendWindow)
    showWindow(nil)
    trendWindow.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func updateLocalization() {
    window?.title = L10n.text("trends.title", "用量趋势")
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
