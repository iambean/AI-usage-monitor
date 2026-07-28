import AppKit
import Foundation
import UniformTypeIdentifiers

struct DiagnosticProviderSnapshot: Codable, Equatable {
  let id: String
  let supportTier: String
  let status: String
  let metricCount: Int
  let updatedAt: Date?
}

struct DiagnosticProcessSnapshot: Codable, Equatable {
  let pid: Int32
  let role: String
  let cpuPercent: Double
  let residentMemoryKB: Int
  let executable: String
}

struct DiagnosticReport: Codable, Equatable {
  let generatedAt: Date
  let appVersion: String
  let buildNumber: String
  let operatingSystem: String
  let architecture: String
  let lowPowerModeEnabled: Bool
  let primaryProvider: String?
  let enabledProviders: [String]
  let providers: [DiagnosticProviderSnapshot]
  let processes: [DiagnosticProcessSnapshot]
}

enum DiagnosticsExporter {
  @MainActor
  static func export(
    states: [ProviderUsageState],
    enabledProviderIDs: [ProviderID],
    lowPowerModeEnabled: Bool
  ) throws -> URL? {
    let panel = NSSavePanel()
    panel.title = L10n.text("diagnostics.exportTitle", "导出诊断包")
    panel.nameFieldStringValue = archiveName()
    panel.allowedContentTypes = [.zip]
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let destination = panel.url else {
      return nil
    }

    DiagnosticLog.flush()
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory
      .appendingPathComponent("AIUsageDiagnostics-\(UUID().uuidString)", isDirectory: true)
    let packageDirectory =
      temporaryRoot
      .appendingPathComponent("AI Usage Diagnostics", isDirectory: true)
    defer {
      try? fileManager.removeItem(at: temporaryRoot)
    }

    try fileManager.createDirectory(
      at: packageDirectory,
      withIntermediateDirectories: true
    )
    let report = makeReport(
      states: states,
      enabledProviderIDs: enabledProviderIDs,
      lowPowerModeEnabled: lowPowerModeEnabled
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    var reportData = try encoder.encode(report)
    reportData.append(0x0A)
    try reportData.write(
      to: packageDirectory.appendingPathComponent("report.json"),
      options: .atomic
    )

    if fileManager.fileExists(atPath: DiagnosticLog.fileURL.path) {
      try fileManager.copyItem(
        at: DiagnosticLog.fileURL,
        to: packageDirectory.appendingPathComponent("diagnostics.log")
      )
    }

    let archiveURL = temporaryRoot.appendingPathComponent("diagnostics.zip")
    try createArchive(packageDirectory: packageDirectory, archiveURL: archiveURL)
    if fileManager.fileExists(atPath: destination.path) {
      try fileManager.removeItem(at: destination)
    }
    try fileManager.copyItem(at: archiveURL, to: destination)
    return destination
  }

  static func makeReport(
    states: [ProviderUsageState],
    enabledProviderIDs: [ProviderID],
    lowPowerModeEnabled: Bool,
    bundle: Bundle = .main,
    processID: Int32 = ProcessInfo.processInfo.processIdentifier
  ) -> DiagnosticReport {
    DiagnosticReport(
      generatedAt: Date(),
      appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        as? String ?? "development",
      buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion")
        as? String ?? "development",
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
      architecture: currentArchitecture,
      lowPowerModeEnabled: lowPowerModeEnabled,
      primaryProvider: enabledProviderIDs.first?.rawValue,
      enabledProviders: enabledProviderIDs.map(\.rawValue),
      providers: states.map {
        DiagnosticProviderSnapshot(
          id: $0.id.rawValue,
          supportTier: ProviderCatalog.metadata(for: $0.id).supportTier.rawValue,
          status: $0.status.rawValue,
          metricCount: $0.metrics.count,
          updatedAt: $0.updatedAt
        )
      },
      processes: processSnapshots(parentPID: processID)
    )
  }

  private static var currentArchitecture: String {
    #if arch(arm64)
      return "arm64"
    #elseif arch(x86_64)
      return "x86_64"
    #else
      return "unknown"
    #endif
  }

  private static func processSnapshots(parentPID: Int32) -> [DiagnosticProcessSnapshot] {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-axo", "pid=,ppid=,%cpu=,rss=,comm="]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return []
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard let text = String(data: data, encoding: .utf8) else { return [] }

    return text.split(separator: "\n").compactMap { line in
      let fields = line.split(
        maxSplits: 4,
        omittingEmptySubsequences: true,
        whereSeparator: \.isWhitespace
      )
      guard fields.count == 5,
        let pid = Int32(fields[0]),
        let ppid = Int32(fields[1]),
        let cpu = Double(fields[2]),
        let rss = Int(fields[3]),
        pid == parentPID || ppid == parentPID
      else {
        return nil
      }
      let executable = URL(fileURLWithPath: String(fields[4])).lastPathComponent
      guard executable != "ps" else { return nil }
      return DiagnosticProcessSnapshot(
        pid: pid,
        role: pid == parentPID ? "app" : "child",
        cpuPercent: cpu,
        residentMemoryKB: rss,
        executable: executable
      )
    }
  }

  static func createArchive(packageDirectory: URL, archiveURL: URL) throws {
    let process = Process()
    let errorPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = [
      "-c",
      "-k",
      "--sequesterRsrc",
      "--keepParent",
      packageDirectory.path,
      archiveURL.path,
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
      let message = String(data: data, encoding: .utf8) ?? "ditto failed"
      throw DiagnosticsExportError.archiveFailed(
        DiagnosticSanitizer.text(message)
      )
    }
  }

  private static func archiveName() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "AI-Usage-Diagnostics-\(formatter.string(from: Date())).zip"
  }
}

enum DiagnosticsExportError: LocalizedError {
  case archiveFailed(String)

  var errorDescription: String? {
    switch self {
    case .archiveFailed:
      return L10n.text("diagnostics.exportFailed", "无法生成诊断包")
    }
  }
}
