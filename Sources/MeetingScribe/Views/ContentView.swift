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
            Divider()
            summarySection
        }
        .frame(minWidth: 640, minHeight: 480)
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

            Text(session.status)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button("设置") { showingSettings = true }
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
                        HStack(alignment: .top, spacing: 8) {
                            Text(formatTime(segment.start))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .leading)
                            Text(segment.speaker.displayName)
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(speakerColor(segment.speaker).opacity(0.15))
                                .foregroundStyle(speakerColor(segment.speaker))
                                .clipShape(.capsule)
                            Text(segment.text)
                        }
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
