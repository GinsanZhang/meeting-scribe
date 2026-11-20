import AppKit
import SwiftUI

/// Copies text to the system clipboard. Used by the workbench header,
/// the summary panel and the floating windows.
func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// The workbench's right panel (design: AI 总结 / 纪要 / 待办).
/// Reads the live session when `meeting` is nil, or a saved meeting
/// otherwise. Todo checkmarks write back (to the session, or to the
/// stored meeting file).
struct SummaryPanel: View {
    enum Tab: String, CaseIterable {
        case summary = "AI 总结"
        case minutes = "纪要"
        case todos = "待办"
    }

    var meeting: SavedMeeting?
    @Binding var tab: Tab

    @EnvironmentObject var session: MeetingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch tab {
                    case .summary: summaryTab
                    case .minutes: minutesTab
                    case .todos: todosTab
                    }
                }
                .padding()
            }
        }
        .frame(width: 260)
    }

    // MARK: - Data (live session or saved meeting)

    private var summaryText: String { meeting?.summary ?? session.summary }
    private var keyPoints: [String] { meeting?.keyPoints ?? session.keyPoints }
    private var todos: [TodoItem] { meeting?.todos ?? session.todos }
    private var isGenerating: Bool { meeting == nil && session.isSummarizing }
    private var canGenerate: Bool {
        meeting == nil && !session.segments.isEmpty && !session.isSummarizing
    }

    private func toggleTodo(_ todo: TodoItem) {
        if var saved = meeting {
            if let index = saved.todos.firstIndex(where: { $0.id == todo.id }) {
                saved.todos[index].done.toggle()
                MeetingStore.shared.save(saved)
            }
        } else {
            session.toggleTodo(todo.id)
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    tab = item
                } label: {
                    HStack(spacing: 4) {
                        if item == .summary {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                        }
                        Text(item.rawValue)
                        if item == .todos && !todos.isEmpty {
                            Text("\(todos.count)")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.1))
                                .clipShape(.capsule)
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(tab == item ? .blue : .secondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button { copyToClipboard(summaryText) } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .disabled(summaryText.isEmpty)
            .help("复制总结")
        }
        .padding(.horizontal, 8)
    }

    // MARK: - AI 总结 tab

    private var summaryTab: some View {
        Group {
            if summaryText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("还没有总结")
                        .font(.headline)
                    Text(canGenerate ? "转录已有内容，点下面生成 AI 总结。" : "开始录音，转录完成后可生成 AI 总结。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if canGenerate {
                        Button("生成总结") { session.generateSummary() }
                    }
                }
            } else {
                summarySection
                if !keyPoints.isEmpty {
                    keyPointsSection
                }
                if !todos.isEmpty {
                    todosSection
                }
            }
            if isGenerating {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("正在生成总结…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("会议摘要")
                .font(.headline)
            Text(summaryText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var keyPointsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("要点提炼")
                .font(.headline)
            ForEach(keyPoints, id: \.self) { point in
                HStack(alignment: .top, spacing: 6) {
                    Text("•").foregroundStyle(.secondary)
                    Text(point).font(.callout)
                }
            }
        }
    }

    private var todosSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("待办事项")
                .font(.headline)
            ForEach(todos) { todo in
                todoRow(todo)
            }
        }
    }

    // MARK: - 纪要 tab

    private var minutesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if summaryText.isEmpty && keyPoints.isEmpty {
                Text("还没有可写入纪要的内容。先录音并生成 AI 总结。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("会议主题")
                        .font(.headline)
                    Text(meetingTitle)
                        .font(.callout)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("时间")
                        .font(.headline)
                    Text(meetingTimeText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if !summaryText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("会议摘要")
                            .font(.headline)
                        Text(summaryText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                if !keyPoints.isEmpty {
                    keyPointsSection
                }
                Button("复制纪要") { copyToClipboard(minutesText) }
            }
        }
    }

    private var meetingTitle: String {
        meeting?.title ?? session.meetingTitle
    }

    private var meetingTimeText: String {
        if let meeting {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd HH:mm"
            return "\(formatter.string(from: meeting.startedAt)) – \(formatter.string(from: meeting.endedAt))"
        }
        if let startedAt = session.startedAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd HH:mm"
            return "\(formatter.string(from: startedAt)) 开始 · 已录 \(formatDuration(session.elapsedSeconds))"
        }
        return "尚未开始"
    }

    private var minutesText: String {
        var parts: [String] = []
        parts.append("会议主题：\(meetingTitle)")
        parts.append("时间：\(meetingTimeText)")
        if !summaryText.isEmpty {
            parts.append("\n会议摘要：\n\(summaryText)")
        }
        if !keyPoints.isEmpty {
            parts.append("\n要点提炼：\n" + keyPoints.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !todos.isEmpty {
            parts.append("\n待办事项：\n" + todos.map { "- [\($0.done ? "x" : " ")] \($0.text)" }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - 待办 tab

    private var todosTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            if todos.isEmpty {
                Text(summaryText.isEmpty
                    ? "还没有待办。生成 AI 总结后，这里的待办事项会自动提取。"
                    : "总结里没有提到待办事项。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(todos) { todo in
                    todoRow(todo)
                }
                Text("勾选状态会保存下来，下次打开这场会议还在。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func todoRow(_ todo: TodoItem) -> some View {
        Button {
            toggleTodo(todo)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: todo.done ? "checkmark.square.fill" : "square")
                    .foregroundStyle(todo.done ? .blue : .secondary)
                Text(todo.text)
                    .font(.callout)
                    .foregroundStyle(todo.done ? .secondary : .primary)
                    .strikethrough(todo.done)
                    .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
    }
}
