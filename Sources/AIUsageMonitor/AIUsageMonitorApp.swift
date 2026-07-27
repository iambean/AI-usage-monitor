import SwiftUI

@main
struct AIUsageMonitorApp: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    MenuBarExtra {
      MenuBarContentView()
        .environmentObject(model)
    } label: {
      HStack(spacing: 4) {
        Image(systemName: model.primaryState.symbolName)
          .symbolRenderingMode(.monochrome)
        Text(menuBarText)
          .monospacedDigit()
      }
      .task {
        model.startIfNeeded()
      }
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView()
        .environmentObject(model)
    }
  }

  private var menuBarText: String {
    guard !model.providerStates.isEmpty else {
      return "—"
    }
    return model.primaryState.summary?.compactDisplayText ?? "—"
  }
}
