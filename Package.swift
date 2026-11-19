// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "meeting-scribe",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MeetingScribe", targets: ["MeetingScribe"])
    ],
    dependencies: [
        // Argmax Open-Source SDK (v1.0.0, 2026-05):
        // SpeakerKit = on-device speaker diarization (Pyannote backend).
        // The old github.com/argmaxinc/WhisperKit URL redirects here.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0"),
        // sherpa-onnx (2.0.1): on-device streaming ASR (Paraformer).
        // SPM product "sherpa-onnx", Swift module SherpaOnnx, backed by
        // a prebuilt macOS XCFramework + onnxruntime.
        .package(url: "https://github.com/k2-fsa/sherpa-onnx", from: "2.0.1")
    ],
    targets: [
        .executableTarget(
            name: "MeetingScribe",
            dependencies: [
                .product(name: "SpeakerKit", package: "argmax-oss-swift"),
                .product(name: "sherpa-onnx", package: "sherpa-onnx")
            ]
        )
    ]
)
