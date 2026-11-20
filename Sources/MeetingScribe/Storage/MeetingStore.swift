import Foundation

/// One saved meeting: the transcript, summary and derived todos,
/// stored as JSON in Application Support. Written when a recording
/// ends; the workbench sidebar (最近 / 会议库) lists read from here.
/// A saved meeting is read-only except for its title and todo
/// checkmarks, which update the stored file.
struct SavedMeeting: Identifiable, Codable {
    let id: UUID
    var title: String
    let startedAt: Date
    let endedAt: Date
    /// MeetingMode rawValue ("online" / "inPerson").
    let mode: String
    /// "在线" / "本地".
    let engine: String
    var segments: [SavedSegment]
    var summary: String
    var keyPoints: [String]
    var todos: [TodoItem]
    /// Bookmarked from the workbench header (the bookmark icon). Shown
    /// in the sidebar and library rows.
    var isBookmarked: Bool = false

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    var speakerCount: Int { Set(segments.map(\.speakerId)).count }

    var transcriptText: String {
        segments.map { "[\(formatTime($0.start))] \($0.speakerName)：\($0.text)" }
            .joined(separator: "\n")
    }
}

struct SavedSegment: Identifiable, Codable {
    let id: UUID
    let text: String
    let start: TimeInterval
    let end: TimeInterval
    let speakerId: String
    let speakerName: String
    /// AudioSource rawValue ("microphone" / "system").
    let source: String
}

struct TodoItem: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    var done: Bool

    init(id: UUID = UUID(), text: String, done: Bool = false) {
        self.id = id
        self.text = text
        self.done = done
    }
}

extension SavedMeeting {
    /// Tolerant decoding: `isBookmarked` was added after the first
    /// saved meetings, so files written before it lack the key. Kept
    /// in an extension so the memberwise initializer survives.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        mode = try container.decode(String.self, forKey: .mode)
        engine = try container.decode(String.self, forKey: .engine)
        segments = try container.decode([SavedSegment].self, forKey: .segments)
        summary = try container.decode(String.self, forKey: .summary)
        keyPoints = try container.decode([String].self, forKey: .keyPoints)
        todos = try container.decode([TodoItem].self, forKey: .todos)
        isBookmarked = try container.decodeIfPresent(Bool.self, forKey: .isBookmarked) ?? false
    }
}

/// File-based meeting library. A singleton: the session saves into it
/// when a recording ends, and every window reads the same list.
/// Files live in Application Support/MeetingScribe/meetings/<uuid>.json.
@MainActor
final class MeetingStore: ObservableObject {
    static let shared = MeetingStore()

    @Published private(set) var meetings: [SavedMeeting] = []

    static let directory: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingScribe/meetings", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private init() {
        load()
    }

    /// Re-read every file, newest first. Safe to call again (e.g. after
    /// an external change); the list is rebuilt from disk.
    func load() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Self.directory,
            includingPropertiesForKeys: nil
        )) ?? []
        var loaded: [SavedMeeting] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let meeting = try? JSONDecoder().decode(SavedMeeting.self, from: data)
            else { continue }
            loaded.append(meeting)
        }
        meetings = loaded.sorted { $0.startedAt > $1.startedAt }
    }

    /// Insert or replace a meeting (by id) and write its file.
    func save(_ meeting: SavedMeeting) {
        guard let data = try? JSONEncoder().encode(meeting) else { return }
        try? data.write(to: Self.directory.appendingPathComponent("\(meeting.id.uuidString).json"))
        if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
            meetings[index] = meeting
        } else {
            meetings.insert(meeting, at: 0)
        }
        meetings.sort { $0.startedAt > $1.startedAt }
    }

    func delete(_ meeting: SavedMeeting) {
        try? FileManager.default.removeItem(
            at: Self.directory.appendingPathComponent("\(meeting.id.uuidString).json")
        )
        meetings.removeAll { $0.id == meeting.id }
    }
}

/// "01:24" below an hour, "1:08:22" above it. formatTime (mm:ss) is
/// for in-recording clocks; durations in the library need hours.
func formatDuration(_ duration: TimeInterval) -> String {
    let total = Int(duration)
    if total >= 3600 {
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
    return String(format: "%02d:%02d", total / 60, total % 60)
}
