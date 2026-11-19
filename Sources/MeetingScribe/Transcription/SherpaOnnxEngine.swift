import Foundation
import SherpaOnnx

/// Downloads and locates the offline ASR model:
/// sherpa-onnx-streaming-paraformer-bilingual-zh-en (int8), ~226 MB
/// (encoder.int8.onnx 158 MB + decoder.int8.onnx 68 MB + tokens.txt).
/// Files live in Application Support so rebuilding the app never wipes
/// them. The model is bilingual (Chinese + English) and, per sherpa's
/// docs, emits no word timestamps.
enum SherpaModelManager {
    /// Official release tarball. The archive has one top-level
    /// directory containing the three files.
    static let downloadURL = URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-paraformer-bilingual-zh-en.tar.bz2")!

    static let requiredFiles = ["encoder.int8.onnx", "decoder.int8.onnx", "tokens.txt"]

    static var modelDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingScribe", isDirectory: true)
            .appendingPathComponent("sherpa-onnx", isDirectory: true)
            .appendingPathComponent("streaming-paraformer-bilingual-zh-en", isDirectory: true)
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
        case extractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .extractionFailed(let detail): return "模型解压失败：\(detail)"
            }
        }
    }

    /// Download the model tarball and extract it into `modelDirectory`.
    /// `onProgress` reports 0...1 during the download; it is called from
    /// a background URLSession queue, so the caller must hop to the main
    /// actor before touching UI state.
    static func download(onProgress: @escaping (Double) -> Void) async throws {
        let delegate = DownloadDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let tempURL = try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            session.downloadTask(with: downloadURL).resume()
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        // The tarball has one top-level directory; strip it so the
        // files land directly in modelDirectory. /usr/bin/tar ships with
        // macOS; this assumes the app runs unsandboxed (true for the
        // current Xcode-run setup).
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xjf", tempURL.path, "-C", modelDirectory.path, "--strip-components=1"]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DownloadError.extractionFailed("tar 退出码 \(process.terminationStatus)")
        }
        guard isDownloaded else {
            throw DownloadError.extractionFailed("解压后缺少模型文件")
        }
    }

    /// URLSessionDownloadDelegate that reports progress and hands the
    /// finished file back through a continuation. Resumes at most once:
    /// both didFinishDownloadingTo and didCompleteWithError fire.
    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let onProgress: (Double) -> Void
        var continuation: CheckedContinuation<URL, Error>?
        private var resumed = false

        init(onProgress: @escaping (Double) -> Void) {
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
}
