import SwiftUI

/// 发言人 tab: one section per speaker — segment count and total
/// speaking time in the header, their segments underneath. Works off
/// [DisplaySegment] so the live session and saved meetings share it.
struct SpeakersView: View {
    let segments: [DisplaySegment]

    private struct SpeakerStats: Identifiable {
        let id: String
        let name: String
        let count: Int
        let speakingTime: TimeInterval
        let segments: [DisplaySegment]
    }

    private var stats: [SpeakerStats] {
        let grouped = Dictionary(grouping: segments, by: \.speakerId)
        return grouped.map { key, value in
            SpeakerStats(
                id: key,
                name: value.first?.speakerName ?? key,
                count: value.count,
                speakingTime: value.reduce(0) { $0 + max(0, $1.end - $1.start) },
                segments: value.sorted { $0.start < $1.start }
            )
        }
        .sorted { $0.speakingTime > $1.speakingTime }
    }

    var body: some View {
        Group {
            if segments.isEmpty {
                ContentUnavailableView(
                    "还没有发言人",
                    systemImage: "person.2",
                    description: Text("开始录音后，这里会按发言人归纳每段话")
                )
            } else {
                List {
                    ForEach(stats) { stat in
                        Section {
                            ForEach(stat.segments) { segment in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(formatTime(segment.start))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, alignment: .leading)
                                    Text(segment.text)
                                }
                                .padding(.vertical, 2)
                            }
                        } header: {
                            HStack(spacing: 8) {
                                Text(stat.name)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(speakerColor(for: stat.id).opacity(0.15))
                                    .foregroundStyle(speakerColor(for: stat.id))
                                    .clipShape(.capsule)
                                Text("\(stat.count) 段 · \(formatDuration(stat.speakingTime))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// 时间轴 tab: the same segments on a vertical time rail — time on
/// the left, a dot on the rail, speaker + text on the right.
struct TranscriptTimelineView: View {
    let segments: [DisplaySegment]

    var body: some View {
        Group {
            if segments.isEmpty {
                ContentUnavailableView(
                    "还没有时间轴",
                    systemImage: "clock",
                    description: Text("开始录音后，这里会按时间顺序排列每段话")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                            HStack(alignment: .top, spacing: 12) {
                                Text(formatTime(segment.start))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .trailing)
                                    .padding(.top, 2)
                                // Rail: a dot with a line continuing
                                // down to the next row (except the last).
                                VStack(spacing: 0) {
                                    Circle()
                                        .fill(speakerColor(for: segment.speakerId))
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 5)
                                    if index < segments.count - 1 {
                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.3))
                                            .frame(width: 2)
                                            .frame(maxHeight: .infinity)
                                    }
                                }
                                .frame(width: 8)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(segment.speakerName)
                                        .font(.caption.bold())
                                        .foregroundStyle(speakerColor(for: segment.speakerId))
                                    Text(segment.text)
                                }
                                .padding(.bottom, 16)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
