import Darwin
import Foundation

actor CodexAppServerClient {
  private let executablePath: String
  private var process: Process?
  private var standardInput: FileHandle?
  private var standardOutput: FileHandle?
  private var standardError: FileHandle?
  private var outputBuffer = Data()
  private var nextRequestID = 1
  private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
  private var notificationContinuation: AsyncStream<CodexNotification>.Continuation?
  private var isStopping = false
  private(set) var launchCount = 0
  private(set) var unexpectedExitCount = 0

  init(executablePath: String) {
    self.executablePath = executablePath
  }

  func notifications() -> AsyncStream<CodexNotification> {
    AsyncStream { continuation in
      notificationContinuation = continuation
    }
  }

  func start() async throws {
    guard process == nil else { return }
    guard FileManager.default.isExecutableFile(atPath: executablePath) else {
      throw CodexClientError.executableNotFound(executablePath)
    }

    let process = Process()
    let inputPipe = Pipe()
    let outputPipe = Pipe()
    let errorPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = ["app-server"]
    process.environment = CodexProcessEnvironment.make(executablePath: executablePath)
    process.standardInput = inputPipe
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty else { return }
      Task {
        await self?.consume(data)
      }
    }
    errorPipe.fileHandleForReading.readabilityHandler = { handle in
      _ = handle.availableData
    }
    process.terminationHandler = { [weak self] terminatedProcess in
      Task {
        await self?.handleTermination(
          process: terminatedProcess,
          exitCode: terminatedProcess.terminationStatus
        )
      }
    }

    try process.run()
    self.process = process
    launchCount += 1
    DiagnosticLog.record(
      "codex_app_server_started",
      providerID: .codex,
      fields: ["launch_count": String(launchCount)]
    )
    standardInput = inputPipe.fileHandleForWriting
    standardOutput = outputPipe.fileHandleForReading
    standardError = errorPipe.fileHandleForReading

    let initializeParams: JSONValue = .object([
      "clientInfo": .object([
        "name": .string("ai_usage_monitor"),
        "title": .string("AI Usage Monitor"),
        "version": .string(
          Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "development"
        ),
      ])
    ])
    _ = try await request(method: "initialize", params: initializeParams)
    try sendNotification(method: "initialized", params: .object([:]))
  }

  func readRateLimits() async throws -> JSONValue {
    try await start()
    return try await request(
      method: "account/rateLimits/read",
      params: .object([:])
    )
  }

  func stop() async {
    isStopping = true
    standardOutput?.readabilityHandler = nil
    standardError?.readabilityHandler = nil

    let activeProcess = process
    if let activeProcess, activeProcess.isRunning {
      activeProcess.terminate()
      for _ in 0..<20 where activeProcess.isRunning {
        try? await Task.sleep(nanoseconds: 50_000_000)
      }
      if activeProcess.isRunning {
        kill(activeProcess.processIdentifier, SIGKILL)
      }
    }

    process = nil
    standardInput = nil
    standardOutput = nil
    standardError = nil
    outputBuffer.removeAll(keepingCapacity: false)
    failPending(with: CodexClientError.processExited(0))
    isStopping = false
  }

  private func request(method: String, params: JSONValue) async throws -> JSONValue {
    let id = nextRequestID
    nextRequestID += 1
    let request = CodexRPCRequest(method: method, id: id, params: params)

    return try await withCheckedThrowingContinuation { continuation in
      pending[id] = continuation
      do {
        try write(request)
      } catch {
        pending.removeValue(forKey: id)
        continuation.resume(throwing: error)
      }
    }
  }

  private func sendNotification(method: String, params: JSONValue) throws {
    try write(CodexRPCNotification(method: method, params: params))
  }

  private func write<Message: Encodable>(_ message: Message) throws {
    guard let standardInput else {
      throw CodexClientError.missingInput
    }

    var data = try JSONEncoder().encode(message)
    data.append(0x0A)
    try standardInput.write(contentsOf: data)
  }

  private func consume(_ data: Data) {
    outputBuffer.append(data)

    while let newline = outputBuffer.firstIndex(of: 0x0A) {
      let line = outputBuffer[..<newline]
      outputBuffer.removeSubrange(...newline)
      guard !line.isEmpty else { continue }
      handleLine(Data(line))
    }
  }

  private func handleLine(_ data: Data) {
    guard let envelope = try? JSONDecoder().decode(CodexRPCEnvelope.self, from: data) else {
      return
    }

    if let id = envelope.id, let continuation = pending.removeValue(forKey: id) {
      if let error = envelope.error {
        continuation.resume(throwing: CodexClientError.rpc(error.message))
      } else {
        continuation.resume(returning: envelope.result ?? .null)
      }
      return
    }

    if let method = envelope.method {
      notificationContinuation?.yield(
        CodexNotification(method: method, params: envelope.params ?? .object([:]))
      )
    }
  }

  private func handleTermination(process terminatedProcess: Process, exitCode: Int32) {
    guard process === terminatedProcess else { return }
    process = nil
    standardInput = nil
    standardOutput = nil
    standardError = nil
    if !isStopping {
      unexpectedExitCount += 1
      DiagnosticLog.record(
        "codex_app_server_exited",
        providerID: .codex,
        fields: [
          "exit_code": String(exitCode),
          "unexpected_exits": String(unexpectedExitCount),
        ]
      )
    }
    failPending(with: CodexClientError.processExited(exitCode))
  }

  private func failPending(with error: Error) {
    let continuations = pending.values
    pending.removeAll()
    for continuation in continuations {
      continuation.resume(throwing: error)
    }
  }
}
