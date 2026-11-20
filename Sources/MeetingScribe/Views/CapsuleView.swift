import SwiftUI

/// 悬浮胶囊模式 (design: 悬浮转录 · 两种模式 — 轻量跟录，不打断工作):
/// a dark capsule that floats above other apps. Collapsed: record
/// square, timer, waveform, one live subtitle line, AI summary and
/// expand buttons. Expanded (快速预览): the last few transcript rows,
/// an optional AI summary, and pause / copy / main-window actions.
///
/// The capsule is always dark (the window forces `.dark`), so the
/// default text colors render white on it in either app theme.
struct CapsuleView: View {
    @EnvironmentObject var session: MeetingSession
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var isExpanded = false
    @State private var showsSummary = false

    var body: some View {
        VStack(spacing: 0) {
            capsuleBar
            if isExpanded {
                expandedPanel
            }
        }
        .frame(width: 560)
        .background(
            RoundedRectangle(cornerRadius: isExpanded ? 20 : 28)
                .fill(Color(red: 0.11, green: 0.11, blue: 0.13).opacity(0.92))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        )
        .background(BorderlessWindowConfigurator(level: .floating))
    }

    // MARK: - Collapsed bar

    private var capsuleBar: some View {
        HStack(spacing: 10) {
            // Red square = stop while recording, red circle = start.
            Button(action: {
                if session.isRecording { session.stop() } else { session.start() }
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red)
                        .frame(width: 32, height: 32)
                    if session.isRecording {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white)
                            .frame(width: 12, height: 12)
                    } else {
                        Circle().fill(Color.white).frame(width: 12, height: 12)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(session.isRecording ? "结束录音" : "开始录音")

            RecordingStatusView()

            if session.isRecording {
                SpectrumBarsView(bars: session.micSpectrum, color: .cyan, height: 20, barWidth: 2)
                    .frame(width: 110)
            }

            Text(capsuleLiveText)
                .font(.system(size: 14))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                if session.summary.isEmpty && !session.segments.isEmpty {
                    session.generateSummary()
                }
                showsSummary = true
                isExpanded = true
            } label: {
                Image(systemName: "sparkles")
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .disabled(session.segments.isEmpty)
            .help("AI 总结")

            Button { isExpanded.toggle() } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "收起预览" : "展开预览")
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
    }

    private var capsuleLiveText: String {
        if !session.liveMicPartial.isEmpty { return session.liveMicPartial }
        if let last = session.segments.last { return last.text }
        return session.isRecording ? "正在聆听…" : session.status
    }

    // MARK: - Expanded preview

    private var recentSegments: [TranscriptSegment] {
        Array(session.segments.suffix(4))
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().background(Color.white.opacity(0.15))

            ForEach(recentSegments) { segment in
                HStack(alignment: .top, spacing: 8) {
                    Text(formatTime(segment.start))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .leading)
                    Text(segment.text)
                        .font(.callout)
                        .lineLimit(2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(segment.id == recentSegments.last?.id ? Color.white.opacity(0.08) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if recentSegments.isEmpty {
                Text("还没有转录内容")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }

            if showsSummary && !session.summary.isEmpty {
                Text(session.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 16) {
                capsuleAction(icon: "sparkles", label: "AI 总结") {
                    if session.summary.isEmpty && !session.segments.isEmpty {
                        session.generateSummary()
                    }
                    showsSummary.toggle()
                }
                capsuleAction(
                    icon: session.isPaused ? "play.fill" : "pause.fill",
                    label: session.isPaused ? "继续" : "暂停"
                ) {
                    if session.isPaused { session.resume() } else { session.pause() }
                }
                .disabled(!session.isRecording)
                capsuleAction(icon: "doc.on.doc", label: "复制全文") {
                    copyToClipboard(session.transcriptText)
                }
                capsuleAction(icon: "arrow.up.left.and.arrow.down.right", label: "主窗口") {
                    openWindow(id: ViewMode.main.rawValue)
                    dismissWindow(id: ViewMode.capsule.rawValue)
                }
                Spacer()
                ViewModeMenu(current: .capsule)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private func capsuleAction(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.callout)
            }
            .foregroundStyle(.white.opacity(0.85))
        }
        .buttonStyle(.plain)
    }
}
