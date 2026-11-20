import SwiftUI

/// 顶部悬浮条模式 (design: 悬浮转录 · 两种模式 — 信息更完整，会议场景
/// 常驻): a white strip docked at the top center of the screen,
/// floating above other apps. Bar: logo, stop/pause, timer + speaker
/// count, waveform + live-text pill, 摘要 (key points), pin (stay on
/// top), expand. Expanded (更多控制): a panel with 实时转录 / AI 总结 /
/// 待办 tabs, 分屏查看 (main window) and collapse.
///
/// The bar is always light (the window forces `.light`), so the
/// default text colors render dark on it in either app theme.
struct TopBarView: View {
    @EnvironmentObject var session: MeetingSession
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var isExpanded = false
    @State private var panelTab: PanelTab = .transcript
    @State private var isPinned = true

    enum PanelTab: String, CaseIterable {
        case transcript = "实时转录"
        case summary = "AI 总结"
        case todos = "待办"
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if isExpanded {
                expandedPanel
            }
        }
        .frame(width: 1200)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.95))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        )
        .background(BorderlessWindowConfigurator(
            level: isPinned ? .floating : .normal,
            dockAtTopCenter: true,
            dockWidth: 1200,
            dockHeight: 48
        ))
    }

    // MARK: - Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "audio.waveform")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("MeetingScribe")
                    .font(.system(size: 14, weight: .semibold))
            }

            Button(action: {
                if session.isRecording { session.stop() } else { session.start() }
            }) {
                Image(systemName: session.isRecording ? "stop.fill" : "circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help(session.isRecording ? "结束录音" : "开始录音")

            Button(action: {
                if session.isPaused { session.resume() } else { session.pause() }
            }) {
                Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .disabled(!session.isRecording)
            .help(session.isPaused ? "继续录音" : "暂停录音")

            HStack(spacing: 4) {
                Text(formatTime(session.elapsedSeconds))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                Text(session.isRecording ? "录制中" : session.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if session.speakerCount > 0 {
                    Text("· \(session.speakerCount) 人")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                if session.isRecording {
                    SpectrumBarsView(bars: session.micSpectrum, color: .blue, height: 16, barWidth: 2)
                        .frame(width: 110)
                }
                Text(topBarLiveText)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.08))
            .clipShape(.capsule)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                panelTab = .summary
                isExpanded = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles").font(.system(size: 11))
                    Text(session.keyPoints.isEmpty ? "摘要" : "摘要 (\(session.keyPoints.count))")
                        .font(.callout)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.07))
                .clipShape(.capsule)
            }
            .buttonStyle(.plain)
            .help("查看 AI 总结")

            Button { isPinned.toggle() } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13))
                    .foregroundStyle(isPinned ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .help(isPinned ? "取消置顶" : "置顶显示")

            Button { isExpanded.toggle() } label: {
                Image(systemName: isExpanded ? "chevron.up" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "收起面板" : "展开面板")
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }

    private var topBarLiveText: String {
        if !session.liveMicPartial.isEmpty { return session.liveMicPartial }
        if let last = session.segments.last { return last.text }
        return session.isRecording ? "正在聆听…" : session.status
    }

    // MARK: - Expanded panel

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            HStack(spacing: 2) {
                ForEach(PanelTab.allCases, id: \.self) { item in
                    Button { panelTab = item } label: {
                        HStack(spacing: 4) {
                            Text(item.rawValue)
                            if item == .todos && !session.todos.isEmpty {
                                Text("\(session.todos.count)")
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.primary.opacity(0.1))
                                    .clipShape(.capsule)
                            }
                        }
                        .font(.callout)
                        .foregroundStyle(panelTab == item ? .blue : .secondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                        .overlay(alignment: .bottom) {
                            if panelTab == item {
                                Rectangle().fill(Color.blue).frame(height: 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    openWindow(id: ViewMode.main.rawValue)
                    dismissWindow(id: ViewMode.topBar.rawValue)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.split.2x1")
                        Text("分屏查看")
                    }
                    .font(.callout)
                }
                .buttonStyle(.plain)
                .help("切换到主窗口")
                ViewModeMenu(current: .topBar)
                Button { isExpanded = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("收起面板")
            }
            .padding(.horizontal, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    switch panelTab {
                    case .transcript:
                        if session.segments.isEmpty {
                            Text("还没有转录内容")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(session.segments.suffix(8)) { segment in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(formatTime(segment.start))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 36, alignment: .leading)
                                    Text(segment.speaker.displayName)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(speakerColor(for: segment.speaker.id).opacity(0.15))
                                        .foregroundStyle(speakerColor(for: segment.speaker.id))
                                        .clipShape(.capsule)
                                    Text(segment.text)
                                        .font(.callout)
                                }
                            }
                        }
                    case .summary:
                        if session.summary.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("还没有总结")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                if !session.segments.isEmpty {
                                    Button("生成总结") { session.generateSummary() }
                                }
                            }
                        } else {
                            Text(session.summary)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    case .todos:
                        if session.todos.isEmpty {
                            Text("还没有待办。生成 AI 总结后，待办事项会自动提取。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(session.todos) { todo in
                                Button { session.toggleTodo(todo.id) } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: todo.done ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(todo.done ? .blue : .secondary)
                                        Text(todo.text)
                                            .font(.callout)
                                            .foregroundStyle(todo.done ? .secondary : .primary)
                                            .strikethrough(todo.done)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 240)
        }
    }
}
