import SwiftUI

struct ContentView: View {
    @StateObject private var session = MeetingSession()
    @AppStorage(SettingsKey.meetingMode) private var modeRaw = MeetingMode.online.rawValue
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcriptList
            livePartialFooter
            Divider()
            summarySection
        }
        .frame(minWidth: 720, minHeight: 540)
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .onAppear {
            session.mode = MeetingMode(rawValue: modeRaw) ?? .online
        }
        .onChange(of: modeRaw) { _, newValue in
            session.mode = MeetingMode(rawValue: newValue) ?? .online
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker("模式", selection: $modeRaw) {
                ForEach(MeetingMode.allCases) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .disabled(session.isRecording)

            Button(session.isRecording ? "停止" : "开始录音") {
                if session.isRecording {
                    session.stop()
                } else {
                    session.start()
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("r", modifiers: [.command])

            if let start = session.recordingStartedAt {
                RecordingClock(start: start)
            } else {
                Text(session.status)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .help("设置")
        }
        .padding()
    }

    private var transcriptList: some View {
        Group {
            if session.segments.isEmpty {
                ContentUnavailableView(
                    "还没有转录内容",
                    systemImage: "waveform",
                    description: Text(session.isRecording ? "正在聆听…" : "点「开始录音」，转录会实时出现在这里")
                )
            } else {
                ScrollViewReader { proxy in
                    List(session.segments) { segment in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(segment.speaker.displayName)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(speakerColor(segment.speaker).opacity(0.15))
                                    .foregroundStyle(speakerColor(segment.speaker))
                                    .clipShape(.capsule)
                                Text(formatTime(segment.start))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Text(segment.text)
                        }
                        .padding(.vertical, 2)
                        .id(segment.id)
                    }
                    .onChange(of: session.segments.count) { _, _ in
                        if let last = session.segments.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    /// Live partial subtitles (local engine only) as a fixed footer
    /// under the list, not rows inside it. The partial text updates
    /// several times a second while someone is speaking; keeping it
    /// out of the List avoids rows appearing/disappearing plus
    /// scrollTo calls during layout, which crashed the app
    /// (EXC_BAD_ACCESS in SwiftUI's view update on 2026-11-19).
    private var livePartialFooter: some View {
        Group {
            if !session.liveMicPartial.isEmpty || !session.liveSystemPartial.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !session.liveMicPartial.isEmpty {
                        livePartialRow(
                            text: session.liveMicPartial,
                            speaker: session.mode == .inPerson ? .unknown : .you
                        )
                    }
                    if !session.liveSystemPartial.isEmpty {
                        livePartialRow(
                            text: session.liveSystemPartial,
                            speaker: .other
                        )
                    }
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }

    private func livePartialRow(text: String, speaker: SpeakerLabel) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("实时")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
            Text(speaker.displayName)
                .font(.caption.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(speakerColor(speaker).opacity(0.15))
                .foregroundStyle(speakerColor(speaker))
                .clipShape(.capsule)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("总结")
                    .font(.headline)
                Spacer()
                if session.isSummarizing {
                    ProgressView().controlSize(.small)
                }
                Button("生成总结") { session.generateSummary() }
                    .disabled(session.segments.isEmpty || session.isSummarizing)
            }
            if !session.summary.isEmpty {
                ScrollView {
                    Text(session.summary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 220)
            }
        }
        .padding()
    }

    private func speakerColor(_ speaker: SpeakerLabel) -> Color {
        switch speaker.id {
        case "you": return .blue
        case "other": return .green
        case "unknown": return .gray
        default:
            // speaker-0, speaker-1, ... cycle through a small palette.
            let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
            let index = Int(speaker.id.dropFirst("speaker-".count)) ?? 0
            return palette[index % palette.count]
        }
    }
}

/// Recording indicator: pulsing red dot + elapsed time, ticking once
/// a second via TimelineView. Only exists while actually recording.
private struct RecordingClock: View {
    let start: Date

    @State private var pulse = false

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { timeline in
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 1.3 : 1)
                    .opacity(pulse ? 0.55 : 1)
                    .animation(
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: pulse
                    )
                    .onAppear { pulse = true }
                Text(elapsedText(now: timeline.date))
                    .font(.callout.monospacedDigit())
            }
        }
    }

    private func elapsedText(now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
