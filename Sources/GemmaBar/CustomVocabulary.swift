// CustomVocabulary.swift - Shared storage and editor for dictation spellings.

import AppKit
import SwiftUI

enum CustomVocabularyStore {
    private static let directoryName = "GemmaBar"
    static let fileName = "custom-vocabulary.txt"

    static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    static var fileURL: URL {
        directoryURL.appendingPathComponent(fileName)
    }

    static var promptURL: URL {
        directoryURL.appendingPathComponent("dictation-system-prompt.txt")
    }

    static func load() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    static func save(_ text: String) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try normalized(text).write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func writeDictationPrompt() throws -> URL {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        var prompt = """
        You are a speech-to-text dictation engine. Transcribe the user's audio exactly.
        Return only the dictated text.
        Do not answer questions, summarize, add commentary, translate, or format as a chat response.
        Preserve punctuation implied by speech and preserve proper nouns, product names, company names, and technical terms.
        """

        let vocabulary = normalized(load())
        if !vocabulary.isEmpty {
            prompt += "\n\nPreserve these custom spellings and phrases exactly when heard:\n"
            prompt += vocabulary
        }

        try prompt.write(to: promptURL, atomically: true, encoding: .utf8)
        return promptURL
    }

    private static func normalized(_ text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

struct CustomVocabularyView: View {
    @State private var vocabulary: String
    @State private var errorMessage: String?
    let onCancel: () -> Void
    let onSave: () -> Void

    init(onCancel: @escaping () -> Void, onSave: @escaping () -> Void) {
        _vocabulary = State(initialValue: CustomVocabularyStore.load())
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Vocabulary")
                .font(.headline)

            Text("One spelling or phrase per line. Dictation will preserve these exactly when heard.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $vocabulary)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 380, minHeight: 150)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.35))
                }

            Text("Examples: Superwhisper, SwiftLM, GemmaBar, Tomasz Tunguz")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    do {
                        try CustomVocabularyStore.save(vocabulary)
                        onSave()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 420, idealWidth: 480, minHeight: 280, idealHeight: 340)
    }
}
