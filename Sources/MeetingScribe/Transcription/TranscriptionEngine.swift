import WhisperKit

enum TranscriptionError: Error, LocalizedError {
    case notPrepared

    var errorDescription: String? {
        switch self {
        case .notPrepared: return "转录引擎尚未加载"
        }
    }
}

protocol TranscriptionEngine: Actor {
    func prepare() async throws
    /// Transcribe 16 kHz mono samples. Segment start/end are relative
    /// to the start of `samples`.
    func transcribe(samples: [Float]) async throws -> [TranscriptionResult]
}

/// On-device Whisper via WhisperKit (Core ML on the Neural Engine).
/// Default model is the multilingual base (~145 MB); switch to
/// "large-v3-v20240930_626MB" in Settings for maximum accuracy,
/// "openai_whisper-tiny" for the fastest debug loop.
actor WhisperKitEngine: TranscriptionEngine {
    private var pipe: WhisperKit?
    private let model: String

    init(model: String = "openai_whisper-base") {
        self.model = model
    }

    func prepare() async throws {
        if pipe != nil { return }
        let config = WhisperKitConfig(model: model, verbose: false, prewarm: true, load: true)
        pipe = try await WhisperKit(config)
    }

    func transcribe(samples: [Float]) async throws -> [TranscriptionResult] {
        guard let pipe else { throw TranscriptionError.notPrepared }
        return try await pipe.transcribe(audioArray: samples)
    }
}
