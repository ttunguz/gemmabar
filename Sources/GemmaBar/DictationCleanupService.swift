// DictationCleanupService.swift - Gemma cleanup client for dictation text.

import Foundation

@MainActor
final class DictationCleanupService {
    private let serverController: ServerController
    private let cleanupModel = "gemma-4-e4b-it-4bit"

    init(serverController: ServerController) {
        self.serverController = serverController
    }

    func clean(transcript: String) async throws -> String {
        let port = serverController.port
        let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180

        let payload = ChatCompletionRequest(
            model: cleanupModel,
            messages: [
                .init(
                    role: "system",
                    content: "Clean up this speech transcript. Fix punctuation, capitalization, spacing, and obvious transcription errors. Preserve every sentence and every repeated phrase; do not summarize, deduplicate, shorten, reorder, or omit content. Preserve the speaker's meaning and style. Normalize these terms exactly: GemmaBar, SwiftLM, Parakeet, Tomasz, Theory Ventures. Output only the cleaned transcript. Do not include reasoning, notes, markdown, or commentary."
                ),
                .init(role: "user", content: transcript)
            ],
            maxTokens: Self.cleanupMaxTokens(for: transcript),
            temperature: 0,
            enableThinking: false,
            noPromptCache: true,
            chatTemplateKwargs: ["enable_thinking": false]
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DictationError.gemmaFailed(String(data: data, encoding: .utf8) ?? "")
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let cleaned = completion.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cleaned.isEmpty else {
            throw DictationError.emptyCleanup
        }
        return normalizeDictationTerms(cleaned)
    }

    private static func cleanupMaxTokens(for transcript: String) -> Int {
        let estimatedTokens = transcript.count / 3 + 128
        return min(max(estimatedTokens, 256), 4096)
    }

    private func normalizeDictationTerms(_ text: String) -> String {
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
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [Message]
    let maxTokens: Int
    let temperature: Float
    let enableThinking: Bool
    let noPromptCache: Bool
    let chatTemplateKwargs: [String: Bool]

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
        case enableThinking = "enable_thinking"
        case noPromptCache = "no_prompt_cache"
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
