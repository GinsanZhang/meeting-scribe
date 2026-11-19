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
        // WhisperKit = on-device Whisper STT (Core ML, Neural Engine),
        // SpeakerKit = on-device speaker diarization (Pyannote backend).
        // The old github.com/argmaxinc/WhisperKit URL redirects here.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "MeetingScribe",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "SpeakerKit", package: "argmax-oss-swift")
            ]
        )
    ]
)
