import Foundation
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
    /// to the start of `samples`. `language` is a Whisper language code
    /// ("zh", "en", …); `nil` lets WhisperKit detect the language.
    /// Returned results are already cleaned: silent windows and
    /// hallucinated sound annotations are dropped, raw special tokens
    /// are stripped from segment text.
    func transcribe(samples: [Float], language: String?) async throws -> [TranscriptionResult]
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

    func transcribe(samples: [Float], language: String?) async throws -> [TranscriptionResult] {
        guard let pipe else { throw TranscriptionError.notPrepared }
        // WhisperKit's defaults decode to English and keep raw special
        // tokens in segment.text — both produce garbage for Chinese
        // meetings, so set them explicitly. `detectLanguage` only takes
        // effect when no language is given (auto-detect mode).
        let options = DecodingOptions(
            language: language,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            suppressBlank: true,
            noSpeechThreshold: 0.6
        )
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        return results.map { result in
            let segments = result.segments.compactMap { segment -> TranscriptionSegment? in
                guard segment.noSpeechProb <= 0.6,
                      let text = TranscriptSanitizer.clean(segment.text)
                else { return nil }
                var segment = segment
                segment.text = text
                return segment
            }
            return TranscriptionResult(
                text: segments.map(\.text).joined(separator: " "),
                segments: segments,
                language: result.language,
                timings: result.timings,
                seekTime: result.seekTime
            )
        }
    }
}

/// Cleans one Whisper segment's text. Returns nil when the segment
/// carries no real speech and should be dropped.
enum TranscriptSanitizer {
    /// Matches a raw Whisper special token such as
    /// `<|startoftranscript|>`, `<|en|>`, `<|0.00|>`, `<|endoftext|>`.
    private static let specialTokenPattern = #"<\|[^|]*\|>"#
    /// Matches text that is a single sound annotation and nothing else,
    /// e.g. "[silence]", "[BLANK_AUDIO]", "(burps)", "[Sigh]".
    /// Legitimate speech that merely *contains* brackets is kept.
    private static let annotationOnlyPattern = #"^\s*[\[\(][^\]\)]*[\]\)]\s*$"#

    static func clean(_ text: String) -> String? {
        var cleaned = text
        if let regex = try? NSRegularExpression(pattern: specialTokenPattern) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if let regex = try? NSRegularExpression(pattern: annotationOnlyPattern),
           regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) != nil {
            return nil
        }
        return cleaned
    }
}
