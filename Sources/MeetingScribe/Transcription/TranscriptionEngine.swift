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
    /// `model` is the WhisperKit model id, e.g. "openai_whisper-small".
    /// Takes effect on first call; later calls with a different model
    /// reload the pipeline.
    func prepare(model: String) async throws
    /// Transcribe 16 kHz mono samples. Segment start/end are relative
    /// to the start of `samples`.
    func transcribe(samples: [Float]) async throws -> [TranscriptionResult]
}

/// On-device Whisper via WhisperKit (Core ML on the Neural Engine).
/// Default model is the multilingual small (~466 MB); switch to
/// "large-v3-v20240930_626MB" in Settings for maximum accuracy,
/// "openai_whisper-tiny" for the fastest debug loop.
/// Note: always use a multilingual model, never a `.en` variant —
/// meetings are in Chinese.
actor WhisperKitEngine: TranscriptionEngine {
    private var pipe: WhisperKit?
    private var loadedModel: String?

    func prepare(model: String) async throws {
        if pipe != nil, loadedModel == model { return }
        let config = WhisperKitConfig(model: model, verbose: false, prewarm: true, load: true)
        pipe = try await WhisperKit(config)
        loadedModel = model
    }

    func transcribe(samples: [Float]) async throws -> [TranscriptionResult] {
        guard let pipe else { throw TranscriptionError.notPrepared }
        return try await pipe.transcribe(audioArray: samples)
    }
}
