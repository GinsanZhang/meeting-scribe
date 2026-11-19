import Foundation
import WhisperKit

/// Owns the recording pipeline: capture -> chunk -> transcribe -> diarize
/// -> labeled transcript. Runs on the main actor; the heavy inference runs
/// in the engine actors, so the UI stays responsive.
@MainActor
final class MeetingSession: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var segments: [TranscriptSegment] = []
    @Published private(set) var summary = ""
    @Published private(set) var isSummarizing = false
    @Published private(set) var status = "就绪"

    @Published var mode: MeetingMode = .online

    private let capture = AudioCaptureEngine()
    private let transcriber = WhisperKitEngine()
    private let diarizer = SpeakerKitDiarizer()
    private var micChunker = AudioChunker()
    private var systemChunker = AudioChunker()
    private var runTask: Task<Void, Never>?
    private var lastEmittedEnd: TimeInterval = 0

    var transcriptText: String {
        segments.map { "[\(formatTime($0.start))] \($0.speaker.displayName)：\($0.text)" }
            .joined(separator: "\n")
    }

    func start() {
        guard !isRecording else { return }
        segments = []
        summary = ""
        lastEmittedEnd = 0
        micChunker = AudioChunker()
        systemChunker = AudioChunker()
        isRecording = true
        runTask = Task { await runLoop() }
    }

    func stop() {
        // Don't cancel the task: let the loop finish the stream and
        // transcribe the tail, then it clears isRecording itself.
        capture.stop()
    }

    func generateSummary() {
        guard !segments.isEmpty, !isSummarizing else { return }
        isSummarizing = true
        Task {
            defer { isSummarizing = false }
            do {
                let provider = SummaryProvider(
                    rawValue: UserDefaults.standard.string(forKey: SettingsKey.summaryProvider) ?? ""
                ) ?? .ollama
                let modelKey: String
                switch provider {
                case .ollama: modelKey = SettingsKey.ollamaModel
                case .openRouter: modelKey = SettingsKey.openRouterModel
                case .siliconFlow: modelKey = SettingsKey.siliconFlowModel
                }
                let model = UserDefaults.standard.string(forKey: modelKey) ?? provider.defaultModel
                let apiKey = provider.needsAPIKey
                    ? KeychainStore.read(account: provider.rawValue) : nil
                let summarizer = SummarizerFactory.make(provider: provider, model: model, apiKey: apiKey)
                summary = try await summarizer.summarize(transcript: transcriptText)
            } catch {
                summary = "总结失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - Pipeline

    private func runLoop() async {
        do {
            status = "正在加载模型…（首次运行会下载 Whisper 模型）"
            try await transcriber.prepare()
            if mode == .inPerson {
                try await diarizer.prepare()
            }
            let stream = try await capture.start(mode: mode)
            status = mode == .online ? "录音中：麦克风 + 系统音" : "录音中：麦克风（线下会议）"
            for await chunk in stream {
                let windows = chunk.source == .microphone
                    ? micChunker.append(chunk.samples, source: .microphone)
                    : systemChunker.append(chunk.samples, source: .system)
                for window in windows {
                    await process(window)
                }
            }
            // Stream ended (stop called): transcribe the tails.
            status = "正在收尾…"
            if let tail = micChunker.flush(source: .microphone) { await process(tail) }
            if let tail = systemChunker.flush(source: .system) { await process(tail) }
            status = "已停止，共 \(segments.count) 段"
        } catch {
            status = "出错：\(error.localizedDescription)"
        }
        isRecording = false
    }

    private func process(_ window: AudioWindow) async {
        do {
            let results = try await transcriber.transcribe(samples: window.samples)
            // In-person mode: diarize the same chunk, then align speakers
            // onto the transcript by time overlap.
            var diarized: [DiarizedSegment] = []
            if mode == .inPerson {
                let expected = UserDefaults.standard.integer(forKey: SettingsKey.expectedSpeakers)
                diarized = try await diarizer.diarize(
                    samples: window.samples,
                    expectedSpeakers: expected > 0 ? expected : nil
                )
            }
            for result in results {
                for segment in result.segments {
                    let start = window.startTime + TimeInterval(segment.start)
                    let end = window.startTime + TimeInterval(segment.end)
                    let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty, end > lastEmittedEnd else { continue }
                    let speaker: SpeakerLabel
                    if mode == .inPerson {
                        let probe = TranscriptSegment(
                            text: text, start: start, end: end,
                            speaker: .unknown, source: window.source
                        )
                        speaker = DiarizationAligner.label(for: probe, in: diarized)
                    } else {
                        // Online: the channel is the label. Mic = you,
                        // system audio = everyone else.
                        speaker = window.source == .microphone ? .you : .other
                    }
                    segments.append(TranscriptSegment(
                        text: text,
                        start: max(start, lastEmittedEnd),
                        end: end,
                        speaker: speaker,
                        source: window.source
                    ))
                    lastEmittedEnd = max(lastEmittedEnd, end)
                }
            }
        } catch {
            // A single window failing must not kill the session.
            print("[MeetingScribe] window failed: \(error)")
        }
    }
}

func formatTime(_ time: TimeInterval) -> String {
    let total = Int(time)
    return String(format: "%02d:%02d", total / 60, total % 60)
}
