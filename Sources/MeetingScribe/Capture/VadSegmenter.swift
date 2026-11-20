import Foundation
import SherpaOnnx

/// One utterance of 16 kHz mono audio handed to the transcription engine.
struct AudioWindow: Sendable {
    let samples: [Float]
    let source: AudioSource
    /// Seconds since the recording started.
    let startTime: TimeInterval
}

/// Cuts the audio stream into utterances with Silero VAD (via
/// sherpa-onnx): speech is buffered until a pause ends it, so each
/// emitted window is one natural sentence instead of a fixed 6 s block.
/// One instance per audio source (mic / system). Owned by
/// MeetingSession (MainActor), so no locking needed.
@MainActor
final class VadSegmenter {
    private var vad: SherpaOnnxVoiceActivityDetectorWrapper?

    /// Longest single utterance, from Settings → 实时性 slider
    /// (3–10 s, default 5). Read at prepare() time, so it applies
    /// from the next recording. Clamped so a stale stored value
    /// can't fragment speech or stall it.
    static var maxSpeechSeconds: Double {
        let raw = UserDefaults.standard.object(forKey: SettingsKey.maxSpeechSeconds) as? Double ?? 5
        return min(max(raw, 3), 10)
    }

    /// Load the VAD model, downloading it first if needed (~2 MB).
    /// Must be called before `append`.
    func prepare() async throws {
        if vad != nil { return }
        if !SherpaModelManager.isVadDownloaded {
            try await SherpaModelManager.downloadVad()
        }
        var modelConfig = sherpaOnnxVadModelConfig(
            sileroVad: sherpaOnnxSileroVadModelConfig(
                model: SherpaModelManager.vadModelPath,
                threshold: 0.5,
                // A 0.3 s pause ends an utterance: short enough to
                // recognize at the natural pauses inside speech
                // (the previous 0.5 s made it feel like recognition
                // waited for a whole sentence to finish), long
                // enough not to split on brief hesitations.
                minSilenceDuration: 0.3,
                minSpeechDuration: 0.25,
                windowSize: 512,
                // A long monologue is cut at the Settings → 实时性
                // value (3–10 s, default 5) so the transcript never
                // lags more than ~that long behind the speaker: a
                // chunk is finalized ~1–2 s after its cut on the
                // online engine (faster locally), instead of one
                // recognition unit growing unbounded until they stop.
                // Clamped: a stale value can't fragment speech or
                // stall it. Applies from the next recording (the
                // segmenters are built per recording).
                maxSpeechDuration: Float(Self.maxSpeechSeconds)
            )
        )
        vad = SherpaOnnxVoiceActivityDetectorWrapper(config: &modelConfig, buffer_size_in_seconds: 60)
    }

    /// Feed new samples; returns any utterances that ended.
    func append(_ samples: [Float], source: AudioSource) -> [AudioWindow] {
        guard let vad else { return [] }
        vad.acceptWaveform(samples: samples)
        return drain(source: source)
    }

    /// Flush at stop: emit the final utterance, if any.
    func flush(source: AudioSource) -> [AudioWindow] {
        guard let vad else { return [] }
        vad.flush()
        return drain(source: source)
    }

    private func drain(source: AudioSource) -> [AudioWindow] {
        guard let vad else { return [] }
        var windows: [AudioWindow] = []
        while !vad.isEmpty() {
            let segment = vad.front()
            // Read everything before pop(): Front() is only valid until
            // the next VAD call. `start` is the absolute sample index
            // in the stream since this detector was created.
            let start = segment.start
            let samples = segment.samples
            vad.pop()
            guard !samples.isEmpty else { continue }
            windows.append(AudioWindow(
                samples: samples,
                source: source,
                startTime: TimeInterval(start) / 16_000
            ))
        }
        return windows
    }
}
