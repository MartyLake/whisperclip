// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "WhisperClip",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "WhisperClip",
            targets: ["WhisperClip"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.1"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "3.32.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.32.3")),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.0"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.1.6"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "WhisperClip",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"])
            ],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("DirectoryService")
            ]
        ),
        .testTarget(
            name: "WhisperClipTests",
            dependencies: [
                "WhisperClip",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Tests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
