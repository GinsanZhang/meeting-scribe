import Foundation
import SpeakerKit

/// One diarized stretch of speech. Times are seconds relative to the
/// audio chunk that was diarized.
struct DiarizedSegment: Sendable {
    /// Nil when the speaker could not be matched to a cluster.
    let speakerId: Int?
    let start: TimeInterval
    let end: TimeInterval
}

enum DiarizationError: Error, LocalizedError {
    case notPrepared

    var errorDescription: String? {
        switch self {
        case .notPrepared: return "声纹引擎尚未加载"
        }
    }
}

protocol SpeakerDiarizer: Actor {
    func prepare() async throws
    /// Diarize 16 kHz mono samples. Pass the expected speaker count when
    /// known (line-up in a small meeting); nil lets the model decide.
    func diarize(samples: [Float], expectedSpeakers: Int?) async throws -> [DiarizedSegment]
}

/// On-device diarization via SpeakerKit (Pyannote backend, same Swift
/// package as WhisperKit). Runs on audio chunks after transcription;
/// the session aligns its segments onto the transcript by time overlap.
/// v2: run diarization concurrently with transcription (see WhisperAX's
/// concurrent mode) and use `addSpeakerInfo(to:strategy:)` for word-level
/// labels once word timings are enabled in DecodingOptions.
actor SpeakerKitDiarizer: SpeakerDiarizer {
    private var kit: SpeakerKit?

    func prepare() async throws {
        if kit != nil { return }
        kit = try await SpeakerKit()
    }

    func diarize(samples: [Float], expectedSpeakers: Int?) async throws -> [DiarizedSegment] {
        guard let kit else { throw DiarizationError.notPrepared }
        let options: (any DiarizationOptions)? = expectedSpeakers.map {
            PyannoteDiarizationOptions(numberOfSpeakers: $0)
        }
        let result = try await kit.diarize(audioArray: samples, options: options)
        return result.segments.map { segment in
            DiarizedSegment(
                speakerId: segment.speaker.speakerId,
                start: TimeInterval(segment.startTime),
                end: TimeInterval(segment.endTime)
            )
        }
    }
}

/// Assigns a speaker to a transcript segment by maximum time overlap
/// with the diarization result. Falls back to `.unknown` when nothing
/// overlaps (e.g. diarization failed for that chunk).
enum DiarizationAligner {
    static func label(for segment: TranscriptSegment, in diarized: [DiarizedSegment]) -> SpeakerLabel {
        var best: DiarizedSegment?
        var bestOverlap: TimeInterval = 0
        for candidate in diarized {
            let overlap = min(segment.end, candidate.end) - max(segment.start, candidate.start)
            if overlap > bestOverlap {
                bestOverlap = overlap
                best = candidate
            }
        }
        guard let best, let speakerId = best.speakerId else { return .unknown }
        return .numbered(speakerId)
    }
}
