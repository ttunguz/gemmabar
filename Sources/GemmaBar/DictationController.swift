// DictationController.swift — Parakeet STT followed by Gemma text cleanup.

import AppKit
import AVFoundation
import Foundation

private let parakeetModel = "mlx-community/parakeet-tdt-0.6b-v2"
private let parakeetChunkDuration = 0
private let parakeetOverlapDuration = 0
private let gemmaCleanupModel = "gemma-4-e4b-it-4bit"

@MainActor
final class DictationController: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case recording(Date)
        case transcribing
        case cleaning
        case error(String)

        var menuTitle: String {
            switch self {
            case .idle:
                return "Dictation: Idle"
            case .recording:
                return "Dictation: Recording"
            case .transcribing:
                return "Dictation: Transcribing"
            case .cleaning:
                return "Dictation: Cleaning"
            case .error(let message):
                return "Dictation Error: \(message)"
            }
        }

        var isRecording: Bool {
            if case .recording = self { return true }
            return false
        }

        var canStartRecording: Bool {
            switch self {
            case .idle, .error:
                return true
            case .recording, .transcribing, .cleaning:
                return false
            }
        }
    }

    private let serverController: ServerController
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var tempDirectory: URL?
    private var lastToggleDate = Date.distantPast

    @Published private(set) var state: State = .idle
    @Published private(set) var lastTranscript: String = ""

    init(serverController: ServerController) {
        self.serverController = serverController
        super.init()
    }

    func toggleRecording() {
        let now = Date()
        guard now.timeIntervalSince(lastToggleDate) > 0.75 else {
            Self.log("Dictation toggle ignored by debounce; state=\(state.menuTitle)")
            return
        }
        lastToggleDate = now

        if state.isRecording {
            Task { await stopAndProcessRecording() }
        } else {
            guard state.canStartRecording else {
                Self.log("Dictation toggle ignored while busy; state=\(state.menuTitle)")
                return
            }
            do {
                try startRecording()
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    func startRecording() throws {
        guard state.canStartRecording else { return }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GemmaBar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("recording.wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw DictationError.recordingFailed
        }

        self.tempDirectory = directory
        self.recordingURL = url
        self.recorder = recorder
        self.state = .recording(Date())
        Self.log("Dictation recording started: \(url.path)")
    }

    func stopAndProcessRecording() async {
        guard let recorder, let recordingURL else { return }
        recorder.stop()
        self.recorder = nil

        do {
            state = .transcribing
            let transcript = try await Self.transcribeWithParakeet(audioURL: recordingURL)

            state = .cleaning
            let cleaned = normalizeDictationTerms(try await cleanWithGemma(transcript: transcript))
            lastTranscript = cleaned
            NSPasteboard.general.clearContents()
            let clipboardWritten = NSPasteboard.general.setString(cleaned, forType: .string)
            Self.log("Dictation cleaned \(cleaned.count) chars; clipboardWritten=\(clipboardWritten)")
            state = .idle
            Self.pasteClipboardIntoFrontmostApp()
        } catch {
            Self.log("Dictation failed: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
        }

        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        self.tempDirectory = nil
        self.recordingURL = nil
    }

    private nonisolated static func transcribeWithParakeet(audioURL: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try runParakeet(audioURL: audioURL)
        }.value
    }

    private nonisolated static func runParakeet(audioURL: URL) throws -> String {
        let parakeetBin = try resolveParakeetBinary()
        log("Resolved Parakeet binary: \(parakeetBin)")
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GemmaBar-Parakeet-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let outputTemplate = "transcript"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: parakeetBin)
        process.arguments = [
            audioURL.path,
            "--model", parakeetModel,
            "--output-format", "json",
            "--output-dir", outputDirectory.path,
            "--output-template", outputTemplate,
            "--bf16",
            "--chunk-duration", String(parakeetChunkDuration),
            "--overlap-duration", String(parakeetOverlapDuration)
        ]
        process.environment = parakeetEnvironment(binaryPath: parakeetBin)

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw DictationError.parakeetFailed(stdout: stdout, stderr: stderr)
        }

        let jsonURL = outputDirectory.appendingPathComponent("\(outputTemplate).json")
        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            throw DictationError.missingParakeetOutput(stdout: stdout, stderr: stderr)
        }

        let data = try Data(contentsOf: jsonURL)
        let response = try JSONDecoder().decode(ParakeetResponse.self, from: data)
        let transcript = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            throw DictationError.emptyTranscript
        }
        return transcript
    }

    private func cleanWithGemma(transcript: String) async throws -> String {
        try await serverController.ensureModelLoaded(.dictation)

        let port = serverController.port
        let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        let cleanupMaxTokens = Self.cleanupMaxTokens(for: transcript)

        let payload = ChatCompletionRequest(
            model: gemmaCleanupModel,
            messages: [
                .init(
                    role: "system",
                    content: "Clean up this speech transcript. Fix punctuation, capitalization, spacing, and obvious transcription errors. Preserve every sentence and every repeated phrase; do not summarize, deduplicate, shorten, reorder, or omit content. Preserve the speaker's meaning and style. Normalize these terms exactly: GemmaBar, SwiftLM, Parakeet, Tomasz, Theory Ventures. Output only the cleaned transcript. Do not include reasoning, notes, markdown, or commentary."
                ),
                .init(role: "user", content: transcript)
            ],
            maxTokens: cleanupMaxTokens,
            temperature: 0,
            enableThinking: false,
            chatTemplateKwargs: ["enable_thinking": false]
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DictationError.gemmaFailed(body)
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let cleaned = completion.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cleaned.isEmpty else {
            throw DictationError.emptyCleanup
        }
        return cleaned
    }

    private nonisolated static func cleanupMaxTokens(for transcript: String) -> Int {
        // Dictation cleanup output is usually close to input length. This keeps
        // 4-minute transcripts safe while avoiding excessive decode budgets.
        let estimatedTokens = transcript.count / 3 + 128
        return min(max(estimatedTokens, 256), 4096)
    }

    private nonisolated func normalizeDictationTerms(_ text: String) -> String {
        var normalized = text
        let replacements: [(String, String)] = [
            (#"\bGemma\s+bar\b"#, "GemmaBar"),
            (#"\bGemmaBar\b"#, "GemmaBar"),
            (#"\bGemabar\b"#, "GemmaBar"),
            (#"\bGEMA\b"#, "Gemma"),
            (#"\bGema\b"#, "Gemma"),
            (#"\bSwift\s+LM\b"#, "SwiftLM"),
            (#"\bParaaki\b"#, "Parakeet"),
            (#"\bparakeet\b"#, "Parakeet")
        ]

        for (pattern, replacement) in replacements {
            normalized = normalized.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return normalized
    }

    private nonisolated static func resolveParakeetBinary() throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates: [String] = [
            home.appendingPathComponent("Documents/coding/parakeet/.venv/bin/parakeet-mlx").path,
            home.appendingPathComponent(".local/bin/parakeet-mlx").path
        ]
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(
                resourceURL
                    .appendingPathComponent("Parakeet", isDirectory: true)
                    .appendingPathComponent(".venv/bin/parakeet-mlx")
                    .path
            )
        }
        if let binary = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return binary
        }
        throw DictationError.parakeetNotFound
    }

    private nonisolated static func parakeetEnvironment(binaryPath: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let binDirectory = (binaryPath as NSString).deletingLastPathComponent
        environment["PATH"] = "\(binDirectory):" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        return environment
    }

    nonisolated static func log(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/gemmabar.log")
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private nonisolated static func pasteClipboardIntoFrontmostApp() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let commandKey = CGEventFlags.maskCommand
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            keyDown?.flags = commandKey
            keyUp?.flags = commandKey
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
}

extension DictationController: AVAudioRecorderDelegate {}

private struct ParakeetResponse: Decodable {
    let text: String
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [Message]
    let maxTokens: Int
    let temperature: Float
    let enableThinking: Bool
    let chatTemplateKwargs: [String: Bool]

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
        case enableThinking = "enable_thinking"
        case chatTemplateKwargs = "chat_template_kwargs"
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}

private enum DictationError: LocalizedError {
    case recordingFailed
    case parakeetNotFound
    case parakeetFailed(stdout: String, stderr: String)
    case missingParakeetOutput(stdout: String, stderr: String)
    case emptyTranscript
    case gemmaFailed(String)
    case emptyCleanup

    var errorDescription: String? {
        switch self {
        case .recordingFailed:
            return "Could not start microphone recording."
        case .parakeetNotFound:
            return "parakeet-mlx not found in the bundled runtime or local Parakeet venv."
        case .parakeetFailed(let stdout, let stderr):
            return "Parakeet failed. \(stdout) \(stderr)"
        case .missingParakeetOutput(let stdout, let stderr):
            return "Parakeet did not write JSON output. \(stdout) \(stderr)"
        case .emptyTranscript:
            return "Parakeet returned an empty transcript."
        case .gemmaFailed(let body):
            return "Gemma cleanup failed. \(body)"
        case .emptyCleanup:
            return "Gemma cleanup returned empty text."
        }
    }
}
