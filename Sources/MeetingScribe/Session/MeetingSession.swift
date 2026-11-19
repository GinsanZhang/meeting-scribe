import Foundation

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
    /// Live partial subtitles, one per audio channel (online meetings
    /// have two). The local engine updates them as speech arrives;
    /// the cloud engine leaves them empty and finalizes per utterance.
    @Published private(set) var liveMicPartial = ""
    @Published private(set) var liveSystemPartial = ""

    @Published var mode: MeetingMode = .online

    private let capture = AudioCaptureEngine()
    private let localMicEngine = SherpaOnnxTranscriptionEngine()
    private let localSystemEngine = SherpaOnnxTranscriptionEngine()
    private let cloudEngine = SiliconFlowTranscriptionEngine()
    private var engineKind: TranscriptionEngineKind = .online
    private let diarizer = SpeakerKitDiarizer()
    private var micSegmenter = VadSegmenter()
    private var systemSegmenter = VadSegmenter()
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
        liveMicPartial = ""
        liveSystemPartial = ""
        lastEmittedEnd = 0
        engineKind = TranscriptionEngineKind(
            rawValue: UserDefaults.standard.string(forKey: SettingsKey.transcriptionEngine) ?? ""
        ) ?? .online
        // Fresh VAD segmenters per recording: the VAD's segment start
        // times are absolute since its creation.
        micSegmenter = VadSegmenter()
        systemSegmenter = VadSegmenter()
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

    /// One streaming recognizer per audio channel. A single sherpa
    /// recognizer is one audio stream: feeding mic + system audio
    /// into the same instance mixes the two speakers into one
    /// hypothesis, and a finishUtterance on one channel resets away
    /// the other channel's in-progress audio. The cloud engine is
    /// stateless per request, so it stays shared.
    private func transcriber(for source: AudioSource) -> any TranscriptionEngine {
        if engineKind == .online { return cloudEngine }
        return source == .microphone ? localMicEngine : localSystemEngine
    }

    // MARK: - Pipeline

    private func runLoop() async {
        do {
            status = engineKind == .online
                ? "正在连接在线识别…"
                : "正在加载离线模型…（首次使用需在设置 → 转录 → 本地识别里下载）"
            if engineKind == .online {
                try await cloudEngine.prepare()
            } else {
                // Two recognizers load the model twice; on the 24 GB
                // MacBook Pro this is acceptable, and it is the only
                // way to keep the two channels separate.
                try await localMicEngine.prepare()
                try await localSystemEngine.prepare()
            }
            // VAD cutting is shared by both engines; the ~2 MB model
            // downloads itself on first use.
            status = "正在准备语音检测…"
            try await micSegmenter.prepare()
            try await systemSegmenter.prepare()
            if mode == .inPerson {
                try await diarizer.prepare()
            }
            let stream = try await capture.start(mode: mode)
            let engineLabel = engineKind == .online ? "在线识别" : "本地识别"
            status = (mode == .online ? "录音中：麦克风 + 系统音" : "录音中：麦克风（线下会议）")
                + " · \(engineLabel)"
            for await chunk in stream {
                // Live partial subtitles (local engine only — the cloud
                // engine returns nil here and finalizes per utterance).
                // A failed append must not kill the session.
                // Per-channel engine: mic and system audio must never
                // share one streaming recognizer.
                let transcriber = transcriber(for: chunk.source)
                if let partial = try? await transcriber.appendAudio(chunk.samples) {
                    if chunk.source == .microphone {
                        if partial != liveMicPartial { liveMicPartial = partial }
                    } else if partial != liveSystemPartial {
                        liveSystemPartial = partial
                    }
                }
                let windows = chunk.source == .microphone
                    ? micSegmenter.append(chunk.samples, source: .microphone)
                    : systemSegmenter.append(chunk.samples, source: .system)
                for window in windows {
                    await finalize(window)
                }
            }
            // Stream ended (stop called): transcribe the tails.
            status = "正在收尾…"
            for tail in micSegmenter.flush(source: .microphone) { await finalize(tail) }
            for tail in systemSegmenter.flush(source: .system) { await finalize(tail) }
            liveMicPartial = ""
            liveSystemPartial = ""
            status = "已停止，共 \(segments.count) 段"
        } catch {
            status = "出错：\(error.localizedDescription)"
        }
        isRecording = false
    }

    /// Finalize one VAD utterance: get its text from the engine, diarize
    /// it (in-person mode), and append it as a segment. A single
    /// utterance failing must not kill the session.
    private func finalize(_ window: AudioWindow) async {
        let transcriber = transcriber(for: window.source)
        do {
            guard let text = try await transcriber.finishUtterance(samples: window.samples),
                  !text.isEmpty
            else {
                clearLivePartial(for: window.source)
                return
            }
            // In-person mode: diarize the same utterance, then align
            // speakers onto the transcript by time overlap.
            var diarized: [DiarizedSegment] = []
            if mode == .inPerson {
                let expected = UserDefaults.standard.integer(forKey: SettingsKey.expectedSpeakers)
                diarized = try await diarizer.diarize(
                    samples: window.samples,
                    expectedSpeakers: expected > 0 ? expected : nil
                )
                if diarized.isEmpty {
                    // Speech was transcribed but diarization found no
                    // speaker — log it so a silent diarization failure
                    // doesn't look like "no speakers in the meeting".
                    print("[MeetingScribe] diarization returned no segments for a \(window.samples.count / 16_000)s utterance")
                }
                // Diarized times are relative to the chunk, but the
                // transcript probe below uses absolute times. Without
                // this shift, only the first window (startTime == 0)
                // could ever match — every later window fell back to
                // `.unknown`.
                diarized = diarized.map { segment in
                    DiarizedSegment(
                        speakerId: segment.speakerId,
                        start: segment.start + window.startTime,
                        end: segment.end + window.startTime
                    )
                }
            }
            let start = window.startTime
            let end = window.startTime + TimeInterval(window.samples.count) / 16_000
            guard end > lastEmittedEnd else {
                clearLivePartial(for: window.source)
                return
            }
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
            clearLivePartial(for: window.source)
        } catch {
            // A single utterance failing must not kill the session.
            print("[MeetingScribe] utterance failed: \(error)")
            clearLivePartial(for: window.source)
        }
    }

    private func clearLivePartial(for source: AudioSource) {
        if source == .microphone {
            liveMicPartial = ""
        } else {
            liveSystemPartial = ""
        }
    }
}

func formatTime(_ time: TimeInterval) -> String {
    let total = Int(time)
    return String(format: "%02d:%02d", total / 60, total % 60)
}
