import Foundation
import MLX
import MLXLLM
import MLXLMCommon

@main
struct TestWeights {
    static func main() async throws {
        let config = ModelConfiguration(id: "mlx-community/gemma-4-26b-a4b-it-4bit")
        let modelContainer = try await LLMModelFactory.shared.loadContainer(from: HubClient.default, using: TokenizersLoader(), configuration: config)
        let context = try await modelContainer.context()

        if let gemma4 = context.model as? Gemma4Model {
            print("Successfully cast to Gemma4Model!")
            let layer0 = gemma4.model.layers[0]
            print("Layer 0 norms:")
            print("post1:", layer0.postFeedforwardLayerNorm1?.weight.max().item(Float.self) ?? "NIL")
            print("pre2:", layer0.preFeedforwardLayerNorm2?.weight.max().item(Float.self) ?? "NIL")
            print("post2:", layer0.postFeedforwardLayerNorm2?.weight.max().item(Float.self) ?? "NIL")
            
            print("Router proj:", layer0.expertsBlock?.router.proj.weight.shape ?? [0])
        }
    }
}
