// ModelRegistry.swift — Maps GemmaBar modes to model paths and server config
// Centralizes the three model configurations that were previously spread across
// three separate launchd plist / shell script invocations.

import Foundation

enum GemmaBarMode: String, CaseIterable {
    case dictation
    case vision
    case text
}

struct ModelProfile {
    let mode: GemmaBarMode
    let displayName: String
    let modelPath: String          // Local directory or HuggingFace ID
    let isAudio: Bool
    let isVision: Bool
    let defaultPort: Int
    let defaultTemp: Float
    let defaultMaxTokens: Int

    var menuTitle: String {
        switch mode {
        case .dictation: return "🎙  Dictation"
        case .vision:    return "👁  Vision"
        case .text:       return "💬 Text"
        }
    }
}

enum ModelRegistry {
    // ── Model paths ──────────────────────────────────────────────────────────
    // Resolve from the user's dictation/ or MLX/ directories, falling back to
    // HuggingFace IDs if not found locally.

    private static let home = FileManager.default.homeDirectoryForCurrentUser
    private static let bundledModelsURL = Bundle.main.resourceURL?
        .appendingPathComponent("Models", isDirectory: true)

    static let profiles: [GemmaBarMode: ModelProfile] = [
        .dictation: ModelProfile(
            mode: .dictation,
            displayName: "Gemma 4 E4B (Cleanup)",
            modelPath: home.path + "/Documents/coding/MLX/models/gemma-4-e4b-it-4bit",
            isAudio: false,
            isVision: false,
            defaultPort: 8087,
            defaultTemp: 0.0,
            defaultMaxTokens: 2048
        ),
        .vision: ModelProfile(
            mode: .vision,
            displayName: "Gemma 4 E2B (Vision)",
            modelPath: home.path + "/Documents/coding/MLX/models/gemma-4-e2b-it-4bit",
            isAudio: false,
            isVision: true,
            defaultPort: 8086,
            defaultTemp: 0.6,
            defaultMaxTokens: 2048
        ),
        .text: ModelProfile(
            mode: .text,
            displayName: "Gemma 4 31B (Text)",
            modelPath: home.path + "/Documents/coding/mlx/models/gemma-4-31b-4bit",
            isAudio: false,
            isVision: false,
            defaultPort: 8090,
            defaultTemp: 0.6,
            defaultMaxTokens: 2048
        )
    ]

    static func profile(for mode: GemmaBarMode) -> ModelProfile {
        profiles[mode]!
    }

    /// Resolve the model path, falling back to a HuggingFace ID if the local
    /// directory doesn't exist.
    static func resolvedModelPath(for mode: GemmaBarMode) -> String {
        let profile = self.profile(for: mode)
        let fm = FileManager.default
        if let bundledModelPath = bundledModelPath(for: mode),
           fm.fileExists(atPath: bundledModelPath, isDirectory: nil) {
            return bundledModelPath
        }
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: profile.modelPath, isDirectory: &isDir), isDir.boolValue {
            return profile.modelPath
        }
        // Fallback: use HuggingFace community ID
        switch mode {
        case .dictation: return "mlx-community/gemma-4-e4b-it-4bit"
        case .vision:    return "mlx-community/gemma-4-e2b-it-4bit"
        case .text:       return "mlx-community/gemma-4-31b-4bit"
        }
    }

    private static func bundledModelPath(for mode: GemmaBarMode) -> String? {
        guard let bundledModelsURL else { return nil }
        let directoryName: String
        switch mode {
        case .dictation:
            directoryName = "gemma-4-e4b-it-4bit"
        case .vision:
            directoryName = "gemma-4-e2b-it-4bit"
        case .text:
            directoryName = "gemma-4-31b-4bit"
        }
        return bundledModelsURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .path
    }
}
