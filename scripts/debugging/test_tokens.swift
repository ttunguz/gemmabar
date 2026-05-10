import Foundation
import MLXLMCommon
import MLX

func run() async throws {
    let factory = LLMModelFactory.shared
    let config = ModelConfiguration(id: "mlx-community/gemma-4-26b-a4b-it-4bit")
    let container = try await factory.loadContainer(from: HubClient.default, using: TokenizersLoader(), configuration: config)
    let context = try await container.context()
    
    let messages: [[String: Any]] = [
        ["role": "user", "content": "What is 2+2?"]
    ]
    let prompt = try context.tokenizer.applyChatTemplate(messages: messages)
    let tokens = context.tokenizer.encode(text: prompt)
    print("PROMPT TEXT:", prompt)
    print("TOKENS:", tokens)
}

Task { try await run(); exit(0) }
RunLoop.main.run()
