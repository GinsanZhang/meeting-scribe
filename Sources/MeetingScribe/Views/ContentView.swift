import SwiftUI

struct ContentView: View {
    /// Owned by the app and shared with the mini window.
    @EnvironmentObject var session: MeetingSession
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.meetingMode) private var modeRaw = MeetingMode.online.rawValue
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if session.isRecording {
                SpectrumStrip(
                    micBars: session.micSpectrum,
                    systemBars: session.systemSpectrum,
                    showSystem: session.mode == .online
                )
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
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

            transportControls

            if session.isRecording {
                RecordingIndicator(elapsed: session.elapsedSeconds, paused: session.isPaused)
            } else {
                Text(session.status)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button { openWindow(id: "mini") } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("打开极简窗口")

            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .help("设置")
        }
        .padding()
    }

    /// Round transport controls, recorder-style: a red record circle,
    /// pause/resume, and stop. Cmd+R starts when idle and stops while
    /// recording (the shortcut lives on whichever button is enabled).
    private var transportControls: some View {
        HStack(spacing: 8) {
            Button(action: { session.start() }) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.red.opacity(0.35), lineWidth: 3)
                    )
            }
            .buttonStyle(.plain)
            .disabled(session.isRecording)
            .opacity(session.isRecording ? 0.35 : 1)
            .keyboardShortcut("r", modifiers: .command)
            .help("开始录音")
            Button(action: {
                if session.isPaused { session.resume() } else { session.pause() }
            }) {
                Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 13))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .disabled(!session.isRecording)
            .help(session.isPaused ? "继续录音" : "暂停录音")
            Button(action: { session.stop() }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .disabled(!session.isRecording)
            .keyboardShortcut("r", modifiers: .command)
            .help("结束录音")
        }
    }

    private var transcriptList: some View {
        Group {
            if session.segments.isEmpty {
                ContentUnavailableView(
                    "还没有转录内容",
                    systemImage: "waveform",
                    description: Text(session.isRecording ? "正在聆听…" : "点左上角的红色录音圆点，转录会实时出现在这里")
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

/// Recording indicator: pulsing red dot + elapsed time (paused time
/// excluded; the session ticks it once a second). Amber and still
/// while paused. Only exists while actually recording.
private struct RecordingIndicator: View {
    let elapsed: TimeInterval
    let paused: Bool

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(paused ? Color.orange : Color.red)
                .frame(width: 8, height: 8)
                .scaleEffect(paused ? 1 : (pulse ? 1.3 : 1))
                .opacity(paused ? 1 : (pulse ? 0.55 : 1))
                .animation(
                    paused ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: pulse
                )
                .onAppear { pulse = true }
            Text(formatTime(elapsed))
                .font(.callout.monospacedDigit())
            if paused {
                Text("已暂停")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
