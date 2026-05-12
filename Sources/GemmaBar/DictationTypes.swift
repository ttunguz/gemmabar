// DictationTypes.swift - Shared value types for GemmaBar dictation.

import Foundation

struct RecordingResult {
    let url: URL
    let temporaryDirectory: URL
    let inputDeviceName: String
}

struct RecordingDiagnostics {
    let url: URL
    let byteCount: Int
    let duration: TimeInterval
    let peakLevel: Float
    let rmsLevel: Float
}

struct SpeechSegment: Equatable {
    let text: String
    let startTime: TimeInterval?
    let endTime: TimeInterval?
}

struct SpeechTranscript: Equatable {
    let text: String
    let duration: TimeInterval?
    let segments: [SpeechSegment]
}

struct TextInsertionTarget: Sendable {
    let processIdentifier: pid_t?
    let applicationName: String
}

enum DictationError: LocalizedError {
    case recordingFailed
    case emptyRecording(RecordingDiagnostics)
    case nativeParakeetUnavailable
    case parakeetNotFound
    case parakeetFailed(stdout: String, stderr: String)
    case missingParakeetOutput(stdout: String, stderr: String)
    case emptyTranscript
    case gemmaFailed(String)
    case emptyCleanup
    case pasteboardWriteFailed
    case accessibilityPermissionRequired
    case noFocusedTextTarget

    var errorDescription: String? {
        switch self {
        case .recordingFailed:
            return "Could not start microphone recording."
        case .emptyRecording(let diagnostics):
            return "Recording was empty or silent: \(diagnostics.byteCount) bytes, \(String(format: "%.2f", diagnostics.duration))s."
        case .nativeParakeetUnavailable:
            return "Swift-native Parakeet is unavailable."
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
        case .pasteboardWriteFailed:
            return "Could not write dictation text to the pasteboard."
        case .accessibilityPermissionRequired:
            return "Accessibility permission is required to paste into other apps."
        case .noFocusedTextTarget:
            return "No focused text target was available for insertion."
        }
    }
}
