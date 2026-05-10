// ServerState.swift — Observable state for GemmaBar

import Foundation

enum ServerState {
    case idle
    case loading
    case ready
    case error(String)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var menuTitle: String {
        switch self {
        case .idle:          return "○ Idle"
        case .loading:       return "◌ Loading model..."
        case .ready:         return "● Ready"
        case .error(let msg): return "⚠ Error: \(msg)"
        }
    }
}

@MainActor
protocol ServerControllerDelegate: AnyObject {
    func serverStateDidChange()
}

@MainActor
final class ServerController: ObservableObject {
    weak var delegate: ServerControllerDelegate?

    private(set) var state: ServerState = .idle {
        didSet { delegate?.serverStateDidChange() }
    }

    private(set) var currentMode: GemmaBarMode?
    private(set) var currentModelName: String?

    /// The port the Hummingbird server listens on. Changes when switching modes.
    var port: Int = 8087

    // ── Server internals (managed by startServer / stopServer) ────────────
    private var swiftlmProcess: Process?
    private var serverTask: Task<Void, Never>?
    private var outputPipe: Pipe?

    // ── Defaults ───────────────────────────────────────────────────────────
    private static let defaultModeKey = "com.gemmabar.defaultMode"

    var defaultMode: GemmaBarMode {
        get {
            let raw = UserDefaults.standard.string(forKey: Self.defaultModeKey) ?? "dictation"
            return GemmaBarMode(rawValue: raw) ?? .dictation
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.defaultModeKey)
        }
    }

    // MARK: — Load Model

    func loadDefaultModel() async {
        await loadModel(defaultMode)
    }

    func loadModel(_ mode: GemmaBarMode) async {
        guard !state.isLoading else { return }

        // Unload current
        unloadModel()

        state = .loading
        currentMode = mode
        let profile = ModelRegistry.profile(for: mode)
        let modelPath = ModelRegistry.resolvedModelPath(for: mode)
        currentModelName = profile.displayName
        port = profile.defaultPort

        // Remember as default for next launch
        defaultMode = mode

        if await serverIsReady(port: profile.defaultPort) {
            state = .ready
            return
        }

        // Start the Hummingbird server with the appropriate model
        do {
            try await startServerWithModel(
                modelPath: modelPath,
                port: profile.defaultPort,
                isAudio: profile.isAudio,
                isVision: profile.isVision,
                temp: profile.defaultTemp,
                maxTokens: profile.defaultMaxTokens
            )
            state = .ready
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func unloadModel() {
        stopServer()
        currentMode = nil
        currentModelName = nil
        state = .idle
    }

    // MARK: — Server Lifecycle

    func startServer() async {
        guard let mode = currentMode else { return }
        await loadModel(mode)
    }

    func restartServer() async {
        guard !state.isLoading, let mode = currentMode else { return }
        await loadModel(mode)
    }

    func stopServer() {
        swiftlmProcess?.terminate()
        swiftlmProcess = nil
        outputPipe = nil
        serverTask?.cancel()
        serverTask = nil
    }

    // MARK: — Hummingbird Server Setup

    private func startServerWithModel(
        modelPath: String,
        port: Int,
        isAudio: Bool,
        isVision: Bool,
        temp: Float,
        maxTokens: Int
    ) async throws {
        // For v1, we launch the existing swiftlm binary as a child process.
        // This avoids duplicating 3000+ lines of server logic and ensures
        // full compatibility with the existing API endpoints.
        //
        // The swiftlm binary handles: model loading, tokenization, streaming,
        // audio interleaving, vision processing, etc.
        //
        // GemmaBar manages: process lifecycle, menu bar UI, mode switching.

        let swiftlmBin = resolveSwiftLMBinary()
        log("Resolved SwiftLM binary: \(swiftlmBin)")
        log("Resolved model path: \(modelPath)")

        guard FileManager.default.fileExists(atPath: swiftlmBin) else {
            throw GemmaBarError.binaryNotFound(swiftlmBin)
        }

        // Build arguments
        var args = [swiftlmBin, "--model", modelPath, "--port", String(port), "--host", "127.0.0.1"]
        args += ["--temp", String(temp)]
        args += ["--max-tokens", String(maxTokens)]
        args += ["--prefill-size", "4096"]

        if isAudio {
            args.append("--audio")
            if let promptFile = try? CustomVocabularyStore.writeDictationPrompt() {
                args += ["--system-prompt-file", promptFile.path]
            }
        }
        if isVision {
            args.append("--vision")
        }
        log("Launching SwiftLM: \(args.joined(separator: " "))")

        // Launch process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: swiftlmBin)
        process.arguments = Array(args.dropFirst()) // drop the binary name
        process.currentDirectoryURL = URL(fileURLWithPath: (swiftlmBin as NSString).deletingLastPathComponent)
        process.environment = swiftLMEnvironment(binaryPath: swiftlmBin)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        outputPipe = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.log(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        try process.run()
        log("SwiftLM process started: PID \(process.processIdentifier)")

        swiftlmProcess = process
        let pid = process.processIdentifier

        // Wait for server to become ready (poll /v1/models)
        serverTask = Task {
            // Monitor the process
            while process.isRunning {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
            }
            self.outputPipe?.fileHandleForReading.readabilityHandler = nil
            // Process exited — update state if we haven't switched away
            if self.currentMode != nil {
                self.state = .error("Server process exited (PID \(pid))")
                self.log("SwiftLM process exited: PID \(pid), status \(process.terminationStatus)")
            }
        }

        // Wait for readiness
        let ready = await waitForServer(port: port, timeout: 60)
        if !ready {
            process.terminate()
            log("SwiftLM server timed out on port \(port)")
            throw GemmaBarError.serverStartTimeout(port: port)
        }
    }

    private func waitForServer(port: Int, timeout: TimeInterval) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            if Task.isCancelled { return false }

            if await serverIsReady(port: port) {
                return true
            }
        }
        return false
    }

    private func serverIsReady(port: Int) async -> Bool {
        let url = URL(string: "http://localhost:\(port)/v1/models")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 2

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               let body = String(data: data, encoding: .utf8),
               body.contains("model") {
                return true
            }
        } catch {
            // Server not ready.
        }
        return false
    }

    private func killExistingServer(on port: Int) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/lsof")
        task.arguments = ["-tiTCP:\(port)", "-sTCP:LISTEN"]

        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        for pidStr in output.components(separatedBy: "\n") {
            if let pid = Int(pidStr.trimmingCharacters(in: .whitespaces)) {
                kill(pid_t(pid), SIGTERM)
            }
        }
    }

    private func resolveSwiftLMBinary() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates: [String] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(
                resourceURL
                    .appendingPathComponent("SwiftLM", isDirectory: true)
                    .appendingPathComponent("SwiftLM")
                    .path
            )
        }
        candidates += [
            home.appendingPathComponent("Documents/coding/gemmabar/.build/arm64-apple-macosx/release/SwiftLM").path,
            home.appendingPathComponent("Documents/coding/gemmabar/.build/arm64-apple-macosx/debug/SwiftLM").path,
            home.appendingPathComponent(".local/bin/swiftlm").path
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates.last!
    }

    private func swiftLMEnvironment(binaryPath: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let binaryDirectory = (binaryPath as NSString).deletingLastPathComponent
        environment["PATH"] = "\(binaryDirectory):" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        environment["MLX_METAL_PATH"] = binaryDirectory
        return environment
    }

    private func log(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/gemmabar.log")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}

// MARK: — Errors

enum GemmaBarError: LocalizedError {
    case binaryNotFound(String)
    case serverStartTimeout(port: Int)

    var errorDescription: String {
        switch self {
        case .binaryNotFound(let path):
            return "swiftlm binary not found at \(path). Install from SharpAI/SwiftLM releases."
        case .serverStartTimeout(let port):
            return "Server failed to start on port \(port) within timeout."
        }
    }
}
