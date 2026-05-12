// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "MLXAudio",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "MLXAudioCore", targets: ["MLXAudioCore"]),
        .library(name: "MLXAudioSTT", targets: ["MLXAudioSTT"]),
    ],
    dependencies: [
        .package(path: "../../mlx-swift"),
        .package(path: "../../mlx-swift-lm"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", .upToNextMajor(from: "1.1.6")),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", .upToNextMajor(from: "0.8.1"))
    ],
    targets: [
        // MARK: - MLXAudioCore
        .target(
            name: "MLXAudioCore",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
            ],
            path: "Sources/MLXAudioCore",
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-warn-concurrency"], .when(configuration: .debug))
            ]
        ),

        // MARK: - MLXAudioSTT
        .target(
            name: "MLXAudioSTT",
            dependencies: [
                "MLXAudioCore",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Transformers", package: "swift-transformers"),
            ],
            path: "Sources/MLXAudioSTT",
            sources: [
                "Generation.swift",
                "MLXAudioSTT.swift",
                "Models/Parakeet/ParakeetAlignment.swift",
                "Models/Parakeet/ParakeetAttention.swift",
                "Models/Parakeet/ParakeetAudio.swift",
                "Models/Parakeet/ParakeetCTCLayers.swift",
                "Models/Parakeet/ParakeetConfig.swift",
                "Models/Parakeet/ParakeetConformer.swift",
                "Models/Parakeet/ParakeetDecodingLogic.swift",
                "Models/Parakeet/ParakeetModel.swift",
                "Models/Parakeet/ParakeetRNNTLayers.swift",
                "Models/Parakeet/ParakeetTokenizer.swift"
            ]
        ),
    ]
)
