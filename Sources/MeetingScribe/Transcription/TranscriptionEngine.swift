import Foundation

enum TranscriptionError: Error, LocalizedError {
    case notPrepared
    case missingAPIKey
    case missingLocalModel
    case requestFailed(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notPrepared: return "转录引擎尚未加载"
        case .missingAPIKey: return "未设置硅基流动 API Key，请在设置 → 转录 → 在线识别里保存"
        case .missingLocalModel: return "未下载离线模型，请在设置 → 转录 → 本地识别里下载"
        case .requestFailed(let detail): return "在线识别请求失败：\(detail)"
        case .badResponse: return "在线识别返回了无法识别的结果"
        }
    }
}

/// One recognized segment. `start`/`end` are seconds relative to the
/// start of the audio window that produced it.
struct RecognizedSegment: Sendable {
    let text: String
    let start: Float
    let end: Float
}

protocol TranscriptionEngine: Actor {
    /// Load the engine (model files, API key check, …).
    func prepare() async throws
    /// Transcribe 16 kHz mono samples. Returned segments are already
    /// cleaned: silent windows and hallucinated sound annotations are
    /// dropped, raw special tokens are stripped from the text.
    func transcribe(samples: [Float]) async throws -> [RecognizedSegment]
}

/// Online transcription via SiliconFlow's Qwen3-ASR-1.7B
/// (`POST /v1/audio/transcriptions`, OpenAI-compatible, multipart file
/// upload). The API takes a whole audio file and returns the full text,
/// so each window is one request — near-real-time with a few seconds of
/// lag, not character-by-character streaming. The API key is the same
/// SiliconFlow key stored in the Keychain for summarization.
actor SiliconFlowTranscriptionEngine: TranscriptionEngine {
    static let modelID = "Qwen/Qwen3-ASR-1.7B"
    static let endpoint = URL(string: "https://api.siliconflow.cn/v1/audio/transcriptions")!

    func prepare() async throws {
        guard KeychainStore.read(account: SummaryProvider.siliconFlow.rawValue) != nil else {
            throw TranscriptionError.missingAPIKey
        }
    }

    func transcribe(samples: [Float]) async throws -> [RecognizedSegment] {
        guard let apiKey = KeychainStore.read(account: SummaryProvider.siliconFlow.rawValue),
              !apiKey.isEmpty
        else { throw TranscriptionError.missingAPIKey }
        // Qwen3-ASR detects the language itself and the endpoint takes
        // no language parameter.
        let wav = WavEncoder.encode(samples: samples, sampleRate: 16_000)
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(boundary: boundary, wav: wav)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranscriptionError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "HTTP \(http.statusCode)"
            throw TranscriptionError.requestFailed(detail)
        }
        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        guard let text = TranscriptSanitizer.clean(decoded.text) else { return [] }
        let duration = Float(samples.count) / 16_000
        return [RecognizedSegment(text: text, start: 0, end: duration)]
    }

    private struct TranscriptionResponse: Decodable {
        let text: String
    }

    private func multipartBody(boundary: String, wav: Data) -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(Self.modelID)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"chunk.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(wav)
        append("\r\n--\(boundary)--\r\n")
        return body
    }
}

/// Minimal 16 kHz mono 16-bit PCM WAV encoder (44-byte header).
enum WavEncoder {
    static func encode(samples: [Float], sampleRate: Int) -> Data {
        var data = Data()
        data.reserveCapacity(44 + samples.count * 2)
        func u32(_ value: UInt32) {
            data.append(contentsOf: withUnsafeBytes(of: value.littleEndian) { Array($0) })
        }
        func u16(_ value: UInt16) {
            data.append(contentsOf: withUnsafeBytes(of: value.littleEndian) { Array($0) })
        }
        func tag(_ string: String) { data.append(Data(string.utf8)) }

        let dataSize = UInt32(samples.count * 2)
        tag("RIFF"); u32(36 + dataSize); tag("WAVE")
        tag("fmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        tag("data"); u32(dataSize)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            u16(UInt16(bitPattern: Int16(clamped * 32767)))
        }
        return data
    }
}

/// Cleans one recognized segment's text. Returns nil when the segment
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
