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
    /// True while the user paused the recording. Capture is suspended
    /// (the stream stays open), so `resume()` picks the same session up.
    @Published private(set) var isPaused = false
    /// Elapsed recording time in seconds, excluding paused time. Ticked
    /// once a second by runLoop; drives the recording clock.
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    /// Live spectrum bars (0...1, 28 per channel) for the spectrum
    /// views. Driven by per-chunk RMS; the bar spread is stylized,
    /// not an FFT.
    @Published private(set) var micSpectrum: [CGFloat] = Array(repeating: 0, count: Self.spectrumBarCount)
    @Published private(set) var systemSpectrum: [CGFloat] = Array(repeating: 0, count: Self.spectrumBarCount)
    /// Live partial subtitles, one per audio channel (online meetings
    /// have two). The local engine updates them as speech arrives;
    /// the cloud engine leaves them empty and finalizes per utterance.
    @Published private(set) var liveMicPartial = ""
    @Published private(set) var liveSystemPartial = ""

    @Published var mode: MeetingMode = .online

    /// Editable meeting title (the workbench header shows it as a text
    /// field). Defaults to the start time; saved with the meeting.
    @Published var meetingTitle = ""
    /// When the current recording started (for the title, the meta line
    /// and the saved meeting).
    @Published private(set) var startedAt: Date?
    /// Key points and todos parsed out of the summary (see
    /// SummaryParsing); empty until a summary exists.
    @Published private(set) var keyPoints: [String] = []
    @Published private(set) var todos: [TodoItem] = []

    /// Whether the current meeting is bookmarked (the workbench
    /// header's bookmark icon). Saved with the meeting.
    @Published var isBookmarked = false

    /// Distinct speakers in the current transcript, for the "N 人" badge.
    var speakerCount: Int { Set(segments.map(\.speaker.id)).count }

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
    private static let spectrumBarCount = 28
    /// Speech RMS is small (typically 0.01–0.1); without this gain the
    /// bars sit at the 2 pt floor and the meter looks dead.
    private static let spectrumGain: CGFloat = 10
    private var elapsedTicker: Task<Void, Never>?
    private var micLevel: CGFloat = 0
    private var systemLevel: CGFloat = 0
    private var spectrumPhase = 0.0
    /// The library id of the meeting this recording is being saved as
    /// (set on the first persist, so later updates replace it).
    private var savedMeetingId: UUID?

    var transcriptText: String {
        segments.map { "[\(formatTime($0.start))] \($0.speaker.displayName)：\($0.text)" }
            .joined(separator: "\n")
    }

    /// Short badge for the floating windows, e.g. "在线" / "本地".
    var engineBadge: String { engineKind == .online ? "在线" : "本地" }

    init() {
        // A real title from the start, so the workbench header never
        // shows the "会议标题" placeholder. start() re-titles per
        // recording.
        meetingTitle = Self.defaultMeetingTitle()
    }

    func start() {
        guard !isRecording else { return }
        segments = []
        summary = ""
        liveMicPartial = ""
        liveSystemPartial = ""
        isPaused = false
        elapsedSeconds = 0
        micSpectrum = Array(repeating: 0, count: Self.spectrumBarCount)
        systemSpectrum = Array(repeating: 0, count: Self.spectrumBarCount)
        micLevel = 0
        systemLevel = 0
        lastEmittedEnd = 0
        startedAt = Date()
        meetingTitle = Self.defaultMeetingTitle()
        keyPoints = []
        todos = []
        isBookmarked = false
        savedMeetingId = nil
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

    /// Pauses capture without ending the session: the audio stream stays
    /// open, the transcript and elapsed time are kept, and `resume()`
    /// continues the same recording.
    func pause() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        capture.pause()
        status = "已暂停"
    }

    func resume() {
        guard isRecording, isPaused else { return }
        capture.resume()
        isPaused = false
        let engineLabel = engineKind == .online ? "在线识别" : "本地识别"
        status = (mode == .online ? "录音中：麦克风 + 系统音" : "录音中：麦克风（线下会议）")
            + " · \(engineLabel)"
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
                updateDerivedSummary()
                // A summary generated after the recording stopped still
                // belongs to the saved meeting: write it back.
                persistCurrentMeeting()
            } catch {
                summary = "总结失败：\(error.localizedDescription)"
            }
        }
    }

    /// Toggles the bookmark on the current meeting and writes it back
    /// to the saved meeting, so the mark survives reopening it.
    func toggleBookmark() {
        isBookmarked.toggle()
        persistCurrentMeeting()
    }

    /// Toggles a parsed todo's checkmark and writes it back to the
    /// saved meeting, so the check survives reopening the meeting.
    func toggleTodo(_ id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].done.toggle()
        persistCurrentMeeting()
    }

    /// Rebuilds the saved meeting from the current session state and
    /// writes it to the library (insert on stop, update after a
    /// summary is generated or a todo is toggled). Done flags survive
    /// a re-parse by matching todo text.
    private func persistCurrentMeeting() {
        guard let startedAt, !segments.isEmpty else { return }
        let id = savedMeetingId ?? UUID()
        savedMeetingId = id
        let doneTexts = Set(todos.filter(\.done).map(\.text))
        let meeting = SavedMeeting(
            id: id,
            title: meetingTitle,
            startedAt: startedAt,
            endedAt: Date(),
            mode: mode.rawValue,
            engine: engineBadge,
            segments: segments.map { segment in
                SavedSegment(
                    id: segment.id,
                    text: segment.text,
                    start: segment.start,
                    end: segment.end,
                    speakerId: segment.speaker.id,
                    speakerName: segment.speaker.displayName,
                    source: segment.source.rawValue
                )
            },
            summary: summary,
            keyPoints: keyPoints,
            todos: todos.map { TodoItem(id: $0.id, text: $0.text, done: doneTexts.contains($0.text)) },
            isBookmarked: isBookmarked
        )
        MeetingStore.shared.save(meeting)
    }

    /// Parses key points / todos out of the fresh summary, keeping the
    /// checked state of todos that survived the re-parse.
    private func updateDerivedSummary() {
        keyPoints = parseKeyPoints(from: summary)
        let doneTexts = Set(todos.filter(\.done).map(\.text))
        todos = parseTodos(from: summary).map { item in
            TodoItem(id: item.id, text: item.text, done: doneTexts.contains(item.text))
        }
    }

    private static func defaultMeetingTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return "会议 \(formatter.string(from: Date()))"
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
        var runError: Error?
        var windowContinuation: AsyncStream<AudioWindow>.Continuation?
        var finalizeTask: Task<Void, Never>?
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
            // Finalize runs on its own sequential task. A finalize is
            // slow — a network round-trip per utterance on the online
            // engine, plus diarization in-person — and awaiting it
            // inside the chunk loop froze the spectrum and live
            // partials for seconds at a time, which reads as "the
            // meter lags my voice". The queue keeps utterances in
            // time order while the chunk loop stays real-time.
            let (windowStream, winContinuation) = AsyncStream<AudioWindow>.makeStream()
            windowContinuation = winContinuation
            finalizeTask = Task {
                for await window in windowStream {
                    await finalize(window)
                }
            }
            // One-second ticker for the recording clock; skips ticks
            // while paused so the clock excludes paused time.
            elapsedTicker = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { return }
                    if isRecording && !isPaused { elapsedSeconds += 1 }
                }
            }
            let engineLabel = engineKind == .online ? "在线识别" : "本地识别"
            status = (mode == .online ? "录音中：麦克风 + 系统音" : "录音中：麦克风（线下会议）")
                + " · \(engineLabel)"
            for await chunk in stream {
                updateSpectrum(for: chunk)
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
                    winContinuation.yield(window)
                }
            }
            // Stream ended (stop called): flush the tails into the
            // queue and let the finalize task finish them.
            status = "正在收尾…"
            for tail in micSegmenter.flush(source: .microphone) { winContinuation.yield(tail) }
            for tail in systemSegmenter.flush(source: .system) { winContinuation.yield(tail) }
            liveMicPartial = ""
            liveSystemPartial = ""
        } catch {
            runError = error
        }
        // Wait for every queued utterance to finish transcribing
        // before reporting the final count.
        windowContinuation?.finish()
        await finalizeTask?.value
        finalizeTask = nil
        windowContinuation = nil
        elapsedTicker?.cancel()
        elapsedTicker = nil
        micSpectrum = Array(repeating: 0, count: Self.spectrumBarCount)
        systemSpectrum = Array(repeating: 0, count: Self.spectrumBarCount)
        isPaused = false
        if let runError {
            status = "出错：\(runError.localizedDescription)"
        } else {
            status = "已停止，共 \(segments.count) 段"
        }
        isRecording = false
        // Save the finished meeting (if anything was transcribed) so
        // the sidebar's 最近 / 会议库 can open it later.
        if !segments.isEmpty {
            persistCurrentMeeting()
        }
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

    // MARK: - Spectrum

    /// Per-chunk RMS -> smoothed level -> 28 bars. The bar spread is
    /// stylized (a sine envelope that drifts with time), scaled by the
    /// real loudness; it is a level meter, not an FFT.
    private func updateSpectrum(for chunk: CapturedAudio) {
        let rms = rootMeanSquare(chunk.samples)
        spectrumPhase += 0.35
        if chunk.source == .microphone {
            micLevel = max(CGFloat(rms), micLevel * 0.92)
            micSpectrum = bars(level: micLevel)
        } else {
            systemLevel = max(CGFloat(rms), systemLevel * 0.92)
            systemSpectrum = bars(level: systemLevel)
        }
    }

    private func bars(level: CGFloat) -> [CGFloat] {
        let scaled = min(1, level * Self.spectrumGain)
        return (0..<Self.spectrumBarCount).map { i in
            scaled * CGFloat(0.3 + 0.7 * abs(sin(spectrumPhase + Double(i) * 0.9)))
        }
    }

    private func rootMeanSquare(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return sqrt(sum / Float(samples.count))
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
