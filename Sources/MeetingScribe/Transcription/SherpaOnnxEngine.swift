import Foundation
import SherpaOnnx

/// Downloads and locates the offline ASR model:
/// sherpa-onnx-streaming-paraformer-bilingual-zh-en (int8), ~226 MB
/// (encoder.int8.onnx 158 MB + decoder.int8.onnx 68 MB + tokens.txt).
/// Files live in Application Support so rebuilding the app never wipes
/// them. The model is bilingual (Chinese + English) and, per sherpa's
/// docs, emits no word timestamps.
enum SherpaModelManager {
    /// The three int8 files, downloaded directly from the author's
    /// Hugging Face repo. (The GitHub release tarball bundles the
    /// fp32 models too — ~1 GB total — and its silent multi-minute
    /// extraction after the progress hit 100% looked like a finished
    /// download that never registered, so it is no longer used.)
    static let modelFiles: [(name: String, url: URL, size: Int64)] = [
        ("encoder.int8.onnx", URL(string: "https://huggingface.co/csukuangfj/sherpa-onnx-streaming-paraformer-bilingual-zh-en/resolve/main/encoder.int8.onnx")!, 158_000_000),
        ("decoder.int8.onnx", URL(string: "https://huggingface.co/csukuangfj/sherpa-onnx-streaming-paraformer-bilingual-zh-en/resolve/main/decoder.int8.onnx")!, 68_000_000),
        ("tokens.txt", URL(string: "https://huggingface.co/csukuangfj/sherpa-onnx-streaming-paraformer-bilingual-zh-en/resolve/main/tokens.txt")!, 76_000),
    ]

    static let requiredFiles = ["encoder.int8.onnx", "decoder.int8.onnx", "tokens.txt"]

    static var sherpaDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingScribe", isDirectory: true)
            .appendingPathComponent("sherpa-onnx", isDirectory: true)
    }

    static var modelDirectory: URL {
        sherpaDirectory.appendingPathComponent("streaming-paraformer-bilingual-zh-en", isDirectory: true)
    }

    /// Silero VAD model (~2 MB), downloaded on first use. It fronts
    /// both transcription engines, so it is not part of the 226 MB
    /// Paraformer download in Settings.
    static let vadDownloadURL = URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx")!

    static var vadModelPath: String { sherpaDirectory.appendingPathComponent("silero_vad.onnx").path }

    static var isVadDownloaded: Bool {
        FileManager.default.fileExists(atPath: vadModelPath)
    }

    static func downloadVad() async throws {
        let (tempURL, _) = try await URLSession.shared.download(from: vadDownloadURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try FileManager.default.createDirectory(at: sherpaDirectory, withIntermediateDirectories: true)
        let dest = URL(fileURLWithPath: vadModelPath)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tempURL, to: dest)
    }

    static var isDownloaded: Bool {
        requiredFiles.allSatisfy { file in
            FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent(file).path)
        }
    }

    static var encoderPath: String { modelDirectory.appendingPathComponent("encoder.int8.onnx").path }
    static var decoderPath: String { modelDirectory.appendingPathComponent("decoder.int8.onnx").path }
    static var tokensPath: String { modelDirectory.appendingPathComponent("tokens.txt").path }

    enum DownloadError: Error, LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let detail): return "模型下载失败：\(detail)"
            }
        }
    }

    /// Download the three int8 model files directly into
    /// `modelDirectory` (no tarball, no extraction). `onProgress`
    /// reports 0...1 across all three files; it is called from a
    /// background URLSession queue, so the caller must hop to the
    /// main actor before touching UI state.
    static func download(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        let totalSize = modelFiles.reduce(0) { $0 + $1.size }
        var completedBytes: Int64 = 0
        for file in modelFiles {
            let baseBytes = completedBytes
            let delegate = DownloadDelegate { fileProgress in
                onProgress((Double(baseBytes) + fileProgress * Double(file.size)) / Double(totalSize))
            }
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            defer { session.finishTasksAndInvalidate() }
            let tempURL = try await withCheckedThrowingContinuation { continuation in
                delegate.continuation = continuation
                session.downloadTask(with: file.url).resume()
            }
            defer { try? FileManager.default.removeItem(at: tempURL) }
            let dest = modelDirectory.appendingPathComponent(file.name)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: tempURL, to: dest)
            completedBytes += file.size
            onProgress(Double(completedBytes) / Double(totalSize))
        }
        guard isDownloaded else {
            throw DownloadError.failed("下载后缺少模型文件")
        }
        // Leftover fp32 files from the old tarball download (which
        // bundled them) — the int8 files are all this app uses.
        for leftover in ["encoder.onnx", "decoder.onnx"] {
            try? FileManager.default.removeItem(at: modelDirectory.appendingPathComponent(leftover))
        }
    }

    /// URLSessionDownloadDelegate that reports progress and hands the
    /// finished file back through a continuation. Resumes at most once:
    /// both didFinishDownloadingTo and didCompleteWithError fire.
    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let onProgress: @Sendable (Double) -> Void
        var continuation: CheckedContinuation<URL, Error>?
        private var resumed = false

        init(onProgress: @escaping @Sendable (Double) -> Void) {
            self.onProgress = onProgress
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            guard totalBytesExpectedToWrite > 0 else { return }
            onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {
            resume(returning: location)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error { resume(throwing: error) }
        }

        private func resume(returning url: URL) {
            guard !resumed else { return }
            resumed = true
            continuation?.resume(returning: url)
        }

        private func resume(throwing error: Error) {
            guard !resumed else { return }
            resumed = true
            continuation?.resume(throwing: error)
        }
    }
}

/// On-device transcription via sherpa-onnx + Paraformer-large
/// (streaming, bilingual Chinese + English, int8, fully offline).
/// The recognizer is created once in `prepare()` (loads ~226 MB of
/// models); each window gets a fresh decode stream via `reset()`.
/// Paraformer emits no word timestamps, so each window yields a single
/// segment spanning the whole window — like the cloud engine.
actor SherpaOnnxTranscriptionEngine: TranscriptionEngine {
    private var recognizer: SherpaOnnxRecognizer?

    func prepare() async throws {
        if recognizer != nil { return }
        guard SherpaModelManager.isDownloaded else {
            throw TranscriptionError.missingLocalModel
        }
        let modelConfig = sherpaOnnxOnlineModelConfig(
            tokens: SherpaModelManager.tokensPath,
            paraformer: sherpaOnnxOnlineParaformerModelConfig(
                encoder: SherpaModelManager.encoderPath,
                decoder: SherpaModelManager.decoderPath
            ),
            numThreads: 2
        )
        let featConfig = sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80)
        var config = sherpaOnnxOnlineRecognizerConfig(
            featConfig: featConfig,
            modelConfig: modelConfig
        )
        // The C calls below block while decoding; they run on this
        // actor (off the main thread), so the UI stays responsive.
        recognizer = SherpaOnnxRecognizer(config: &config)
    }

    func transcribe(samples: [Float]) async throws -> [RecognizedSegment] {
        guard let recognizer else { throw TranscriptionError.notPrepared }
        // Paraformer is bilingual and detects the language itself.
        recognizer.acceptWaveform(samples: samples)
        // 0.2 s of silence flushes the last frames through the encoder
        // (same tail padding as sherpa-onnx's Swift file example).
        recognizer.acceptWaveform(samples: [Float](repeating: 0, count: 3200))
        recognizer.inputFinished()
        while recognizer.isReady() {
            recognizer.decode()
        }
        let text = TranscriptSanitizer.clean(recognizer.getResult().text)
        recognizer.reset()
        guard let text else { return [] }
        let duration = Float(samples.count) / 16_000
        return [RecognizedSegment(text: text, start: 0, end: duration)]
    }

    /// Streaming partials: feed audio as it arrives, decode what is
    /// ready, and return the running hypothesis. The caller shows it
    /// as a live subtitle; `finishUtterance` turns it into a segment.
    func appendAudio(_ samples: [Float]) async throws -> String? {
        guard let recognizer else { throw TranscriptionError.notPrepared }
        recognizer.acceptWaveform(samples: samples)
        while recognizer.isReady() {
            recognizer.decode()
        }
        return TranscriptSanitizer.clean(recognizer.getResult().text)
    }

    func finishUtterance(samples: [Float]) async throws -> String? {
        guard let recognizer else { throw TranscriptionError.notPrepared }
        // `samples` is ignored: the utterance audio is already in the
        // stream (fed via appendAudio), including the trailing silence
        // the VAD waited for. A short silence pad flushes the last
        // frames, then the stream resets for the next utterance.
        recognizer.acceptWaveform(samples: [Float](repeating: 0, count: 3200))
        while recognizer.isReady() {
            recognizer.decode()
        }
        let text = TranscriptSanitizer.clean(recognizer.getResult().text)
        recognizer.reset()
        return text
    }
}
