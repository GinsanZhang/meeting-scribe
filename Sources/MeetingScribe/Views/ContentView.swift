import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The workbench main window (design: 方案 B 全新工作台):
/// sidebar (记录 / 会议库 / 知识 / 最近 / 设置) + center
/// (transport, meeting title, 转录 / 发言人 / 时间轴, live partials,
/// real-time summary bar) + right panel (AI 总结 / 纪要 / 待办).
///
/// The center shows the live session, or a saved meeting opened from
/// the sidebar (read-only, with a way back to the live recording).
/// Recording keeps running while a saved meeting is open.
struct ContentView: View {
    /// Owned by the app and shared with the other view modes.
    @EnvironmentObject var session: MeetingSession
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @StateObject private var store = MeetingStore.shared

    @AppStorage(SettingsKey.meetingMode) private var modeRaw = MeetingMode.online.rawValue
    @State private var showingSettings = false

    @State private var sidebarSelection: SidebarSelection = .live
    @State private var selectedMeetingId: UUID?
    @State private var centerTab: CenterTab = .transcript
    @State private var summaryTab: SummaryPanel.Tab = .summary
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var speakerFilter: String? = nil

    enum SidebarSelection { case live, library, knowledge }
    enum CenterTab: String, CaseIterable {
        case transcript = "转录"
        case speakers = "发言人"
        case timeline = "时间轴"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
            Divider()
            centerColumn
            Divider()
            SummaryPanel(meeting: selectedMeeting, tab: $summaryTab)
        }
        .frame(minWidth: 960, minHeight: 600)
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .onAppear {
            session.mode = MeetingMode(rawValue: modeRaw) ?? .online
        }
        .onChange(of: modeRaw) { _, newValue in
            session.mode = MeetingMode(rawValue: newValue) ?? .online
        }
    }

    /// Whether the meeting shown in the center is bookmarked (the
    /// header's bookmark icon): the saved meeting's flag, or the live
    /// session's.
    private var isBookmarked: Bool {
        if let meeting = selectedMeeting { return meeting.isBookmarked }
        return session.isBookmarked
    }

    private func toggleBookmark() {
        if var meeting = selectedMeeting {
            meeting.isBookmarked.toggle()
            MeetingStore.shared.save(meeting)
        } else {
            session.toggleBookmark()
        }
    }

    /// Switches to a floating mode: open the target window first,
    /// then dismiss this one, so a view is always visible.
    private func switchMode(_ mode: ViewMode) {
        openWindow(id: mode.rawValue)
        dismissWindow(id: ViewMode.main.rawValue)
    }

    // MARK: - Selection

    /// The saved meeting open in the center, if any. Looked up from
    /// the store by id (not held as a copy) so todo checkmarks and
    /// title edits made in the panel write straight back through.
    private var selectedMeeting: SavedMeeting? {
        guard let id = selectedMeetingId else { return nil }
        return store.meetings.first { $0.id == id }
    }

    private var isViewingSavedMeeting: Bool { selectedMeeting != nil }

    /// Segments shown in the center tabs: the open meeting's, or the
    /// live session's.
    private var displayedSegments: [DisplaySegment] {
        if let meeting = selectedMeeting {
            return meeting.segments.map { DisplaySegment($0) }
        }
        return session.segments.map { DisplaySegment($0) }
    }

    /// Segments after the search text / speaker filter.
    private var filteredSegments: [DisplaySegment] {
        var list = displayedSegments
        if let speakerFilter {
            list = list.filter { $0.speakerId == speakerFilter }
        }
        if !searchText.isEmpty {
            list = list.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
        }
        return list
    }

    private var displayedSpeakers: [(id: String, name: String)] {
        displayedSegments.reduce(into: [(String, String)]()) { acc, segment in
            if !acc.contains(where: { $0.0 == segment.speakerId }) {
                acc.append((segment.speakerId, segment.speakerName))
            }
        }
    }

    private var displayedTranscriptText: String {
        if let meeting = selectedMeeting { return meeting.transcriptText }
        return session.transcriptText
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarNavButton(icon: "waveform", label: "记录", selected: sidebarSelection == .live && selectedMeetingId == nil) {
                sidebarSelection = .live
                selectedMeetingId = nil
            }
            sidebarNavButton(icon: "calendar", label: "会议库", selected: sidebarSelection == .library) {
                sidebarSelection = .library
            }
            sidebarNavButton(icon: "info.circle", label: "知识", selected: sidebarSelection == .knowledge) {
                sidebarSelection = .knowledge
            }

            Text("最近")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 16)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            if store.meetings.isEmpty {
                Text("还没有保存的会议\n录完一段会自动出现在这里")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            } else {
                ForEach(store.meetings.prefix(8)) { meeting in
                    Button {
                        sidebarSelection = .live
                        selectedMeetingId = meeting.id
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(meeting.title)
                                .lineLimit(1)
                            if meeting.isBookmarked {
                                Image(systemName: "bookmark.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.blue)
                            }
                            Spacer()
                            Text(formatDuration(meeting.duration))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedMeetingId == meeting.id ? Color.blue.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                    .contextMenu {
                        Button("删除", role: .destructive) {
                            store.delete(meeting)
                            if selectedMeetingId == meeting.id { selectedMeetingId = nil }
                        }
                    }
                }
            }

            Spacer()

            sidebarNavButton(icon: "gearshape", label: "设置", selected: false) {
                showingSettings = true
            }
        }
        .padding(.vertical, 8)
        .frame(width: 200)
    }

    private func sidebarNavButton(icon: String, label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(label)
                Spacer()
                if session.isRecording && label == "记录" {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? Color.blue.opacity(0.12) : Color.clear)
            .foregroundStyle(selected ? .blue : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }

    // MARK: - Center

    private var centerColumn: some View {
        VStack(spacing: 0) {
            switch sidebarSelection {
            case .library:
                libraryView
            case .knowledge:
                knowledgeView
            case .live:
                liveCenter
            }
        }
    }

    private var liveCenter: some View {
        VStack(spacing: 0) {
            if isViewingSavedMeeting {
                savedMeetingHeader
            } else {
                liveHeader
            }
            titleRow
            centerTabBar
            Divider()
            tabContent
                .frame(maxHeight: .infinity)
            if !isViewingSavedMeeting {
                LivePartialFooterView()
                realtimeSummaryBar
            }
        }
    }

    private var liveHeader: some View {
        HStack(spacing: 10) {
            TransportControls(size: 28)

            if session.isRecording {
                RecordingIndicator(elapsed: session.elapsedSeconds, paused: session.isPaused)
            } else {
                Text(formatTime(session.elapsedSeconds))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(session.status)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if session.isRecording {
                SpectrumStrip(
                    micBars: session.micSpectrum,
                    systemBars: session.systemSpectrum,
                    showSystem: session.mode == .online,
                    height: 14,
                    barWidth: 2
                )
                .frame(maxWidth: 180)
            }

            Spacer()

            Button { toggleBookmark() } label: {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(isBookmarked ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .help(isBookmarked ? "取消收藏" : "收藏这场会议")

            HStack(spacing: 4) {
                Image(systemName: "person.2")
                    .font(.system(size: 11))
                Text("\(session.speakerCount)")
                    .font(.callout)
            }
            .foregroundStyle(.secondary)
            .help("\(session.speakerCount) 位发言人")
            .opacity(session.speakerCount > 0 ? 1 : 0)

            Menu {
                Button("切换到悬浮胶囊") { switchMode(.capsule) }
                Button("切换到顶部悬浮条") { switchMode(.topBar) }
                Divider()
                Button("导出 .txt") { exportTranscript() }
                Button("复制全文") { copyToClipboard(displayedTranscriptText) }
                Button("复制总结") { copyToClipboard(session.summary) }
                    .disabled(session.summary.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("更多")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var savedMeetingHeader: some View {
        HStack(spacing: 10) {
            Button {
                selectedMeetingId = nil
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("返回当前录音")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            Spacer()

            Button { toggleBookmark() } label: {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(isBookmarked ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .help(isBookmarked ? "取消收藏" : "收藏这场会议")

            Button { copyToClipboard(displayedTranscriptText) } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .help("复制全文")

            Menu {
                Button("导出 .txt") { exportTranscript() }
                Button("复制全文") { copyToClipboard(displayedTranscriptText) }
                if let meeting = selectedMeeting {
                    Button("删除这场会议", role: .destructive) {
                        store.delete(meeting)
                        selectedMeetingId = nil
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("更多")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var titleRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("会议标题", text: titleBinding)
                .font(.title3.bold())
                .textFieldStyle(.plain)
            Text(meetingMetaText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var titleBinding: Binding<String> {
        if let meeting = selectedMeeting {
            return Binding(
                get: { meeting.title },
                set: { newValue in
                    var updated = meeting
                    updated.title = newValue
                    MeetingStore.shared.save(updated)
                }
            )
        }
        return $session.meetingTitle
    }

    private var meetingMetaText: String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        if let meeting = selectedMeeting {
            return "\(dayLabel(for: meeting.startedAt)) \(timeFormatter.string(from: meeting.startedAt)) – \(timeFormatter.string(from: meeting.endedAt)) · \(meeting.speakerCount) 位发言人 · \(formatDuration(meeting.duration))"
        }
        if let startedAt = session.startedAt {
            return "\(dayLabel(for: startedAt)) \(timeFormatter.string(from: startedAt)) 开始 · \(session.mode.displayName) · \(session.speakerCount) 位发言人 · \(formatDuration(session.elapsedSeconds))"
        }
        return "尚未开始录音"
    }

    private func dayLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "今天" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: date)
    }

    private var centerTabBar: some View {
        HStack(spacing: 8) {
            ForEach(CenterTab.allCases, id: \.self) { tab in
                Button {
                    centerTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.callout)
                        .foregroundStyle(centerTab == tab ? .blue : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(centerTab == tab ? Color.blue.opacity(0.12) : Color.clear)
                        .clipShape(.capsule)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if isSearching {
                TextField("搜索转录…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            }
            Button {
                if isSearching { searchText = "" }
                isSearching.toggle()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("搜索转录")
            Menu {
                Button("全部发言人") { speakerFilter = nil }
                ForEach(displayedSpeakers, id: \.0) { speaker in
                    Button(speaker.1) { speakerFilter = speaker.0 }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(speakerFilter == nil ? .secondary : .blue)
            }
            .menuStyle(.borderlessButton)
            .help("按发言人筛选")
        }
        .padding(.horizontal)
    }

    private var tabContent: some View {
        Group {
            switch centerTab {
            case .transcript:
                TranscriptListView(
                    segments: filteredSegments,
                    emptyDescription: isViewingSavedMeeting ? "这场会议没有转录内容" : "点左上角的红色录音圆点，转录会实时出现在这里"
                )
            case .speakers:
                SpeakersView(segments: filteredSegments)
            case .timeline:
                TranscriptTimelineView(segments: filteredSegments)
            }
        }
    }

    private var realtimeSummaryBar: some View {
        Button {
            summaryTab = .summary
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                Text("实时摘要")
                    .fontWeight(.semibold)
                Text(realtimeSummaryText)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color.blue.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var realtimeSummaryText: String {
        if !session.keyPoints.isEmpty {
            return "识别到 \(session.keyPoints.count) 个要点…"
        }
        if !session.summary.isEmpty {
            return "已生成总结，点击查看"
        }
        if session.isRecording {
            return "转录中，生成总结后要点会出现在这里…"
        }
        if !session.segments.isEmpty {
            return "转录已有 \(session.segments.count) 段，点「生成总结」"
        }
        return "开始录音后，这里会显示实时要点"
    }

    // MARK: - Library & knowledge

    private var libraryView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("会议库")
                .font(.title3.bold())
                .padding()
            Divider()
            if store.meetings.isEmpty {
                ContentUnavailableView(
                    "还没有保存的会议",
                    systemImage: "calendar",
                    description: Text("录完一段会议后，它会自动出现在这里")
                )
            } else {
                List(store.meetings) { meeting in
                    Button {
                        sidebarSelection = .live
                        selectedMeetingId = meeting.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(meeting.title).font(.headline)
                                    if meeting.isBookmarked {
                                        Image(systemName: "bookmark.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.blue)
                                    }
                                }
                                Text("\(dayLabel(for: meeting.startedAt)) \(timeString(meeting.startedAt)) · \(meeting.speakerCount) 位发言人 · \(meeting.segments.count) 段")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(formatDuration(meeting.duration))
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("删除", role: .destructive) {
                            store.delete(meeting)
                            if selectedMeetingId == meeting.id { selectedMeetingId = nil }
                        }
                    }
                }
            }
        }
    }

    private var knowledgeView: some View {
        ContentUnavailableView(
            "知识库",
            systemImage: "book",
            description: Text("会议的要点与待办以后会沉淀到这里，现在先在右侧的 AI 总结里查看。")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Export

    private func exportTranscript() {
        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        panel.nameFieldStringValue = "meeting-\(formatter.string(from: Date())).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? displayedTranscriptText.write(to: url, atomically: true, encoding: .utf8)
    }
}
