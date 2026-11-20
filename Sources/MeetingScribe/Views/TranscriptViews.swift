import SwiftUI

/// One transcript row for the workbench tabs, whether it comes from
/// the live session or a saved meeting.
struct DisplaySegment: Identifiable {
    let id: UUID
    let text: String
    let start: TimeInterval
    let end: TimeInterval
    let speakerId: String
    let speakerName: String

    init(_ segment: TranscriptSegment) {
        id = segment.id
        text = segment.text
        start = segment.start
        end = segment.end
        speakerId = segment.speaker.id
        speakerName = segment.speaker.displayName
    }

    init(_ segment: SavedSegment) {
        id = segment.id
        text = segment.text
        start = segment.start
        end = segment.end
        speakerId = segment.speakerId
        speakerName = segment.speakerName
    }
}

/// Transcript pieces shared by the main window, so the workbench
/// tabs show the same list, the same live footer and the same
/// summary. Moved out of ContentView verbatim — behavior unchanged.
///
/// RED LINE (from the 2026-11-19 crash fix): live subtitles stay in
/// the fixed footer under the list, never as rows inside it.
struct TranscriptListView: View {
    @EnvironmentObject var session: MeetingSession

    /// nil = the live session's segments. Pass saved or filtered
    /// segments to show a meeting or a search result instead.
    var segments: [DisplaySegment]? = nil
    var emptyDescription: String = "点左上角的红色录音圆点，转录会实时出现在这里"

    var body: some View {
        let shown = segments ?? session.segments.map { DisplaySegment($0) }
        Group {
            if shown.isEmpty {
                ContentUnavailableView(
                    "还没有转录内容",
                    systemImage: "waveform",
                    description: Text(session.isRecording ? "正在聆听…" : emptyDescription)
                )
            } else {
                ScrollViewReader { proxy in
                    List(shown) { segment in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(segment.speakerName)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(speakerColor(for: segment.speakerId).opacity(0.15))
                                    .foregroundStyle(speakerColor(for: segment.speakerId))
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
                    .onChange(of: shown.count) { _, _ in
                        if let last = shown.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
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
struct LivePartialFooterView: View {
    @EnvironmentObject var session: MeetingSession

    var body: some View {
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
                .background(speakerColor(for: speaker.id).opacity(0.15))
                .foregroundStyle(speakerColor(for: speaker.id))
                .clipShape(.capsule)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

struct SummarySectionView: View {
    @EnvironmentObject var session: MeetingSession

    var body: some View {
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
}

func speakerColor(for speakerId: String) -> Color {
    switch speakerId {
    case "you": return .blue
    case "other": return .green
    case "unknown": return .gray
    default:
        // speaker-0, speaker-1, ... cycle through a small palette.
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
        let index = Int(speakerId.dropFirst("speaker-".count)) ?? 0
        return palette[index % palette.count]
    }
}
