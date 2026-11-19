import Foundation

/// 线上会议：麦克风 + 系统音双通道；线下会议：单个麦克风收全屋声音。
enum MeetingMode: String, CaseIterable, Identifiable {
    case online
    case inPerson

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .online: return "线上会议"
        case .inPerson: return "线下会议"
        }
    }
}

enum AudioSource: String, Sendable {
    case microphone
    case system
}

/// Who is speaking. Online meetings get this from the channel for free
/// (mic = you, system audio = everyone else); in-person meetings get it
/// from SpeakerKit diarization.
struct SpeakerLabel: Hashable, Sendable {
    let id: String
    let displayName: String

    static let you = SpeakerLabel(id: "you", displayName: "我")
    static let other = SpeakerLabel(id: "other", displayName: "对方")
    static let unknown = SpeakerLabel(id: "unknown", displayName: "未知")

    static func numbered(_ index: Int) -> SpeakerLabel {
        SpeakerLabel(id: "speaker-\(index)", displayName: "说话人 \(index + 1)")
    }
}

struct TranscriptSegment: Identifiable, Sendable {
    let id = UUID()
    let text: String
    /// Seconds since the recording started.
    let start: TimeInterval
    let end: TimeInterval
    let speaker: SpeakerLabel
    let source: AudioSource
}

enum SummaryProvider: String, CaseIterable, Identifiable {
    case ollama
    case openRouter
    case siliconFlow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: return "本地 Ollama"
        case .openRouter: return "OpenRouter"
        case .siliconFlow: return "硅基流动"
        }
    }

    var defaultModel: String {
        switch self {
        case .ollama: return "qwen2.5:7b"
        case .openRouter: return "qwen/qwen2.5-7b-instruct"
        case .siliconFlow: return "Qwen/Qwen2.5-7B-Instruct"
        }
    }

    /// OpenAI-compatible chat completions endpoint. Ollama uses its own /api/chat.
    var chatCompletionsURL: URL? {
        switch self {
        case .ollama: return nil
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1/chat/completions")
        case .siliconFlow: return URL(string: "https://api.siliconflow.cn/v1/chat/completions")
        }
    }

    var needsAPIKey: Bool { self != .ollama }
}

/// UserDefaults keys for settings. API keys themselves live in the Keychain,
/// never in UserDefaults and never in the repo.
enum SettingsKey {
    static let summaryProvider = "summaryProvider"
    static let ollamaModel = "ollamaModel"
    static let openRouterModel = "openRouterModel"
    static let siliconFlowModel = "siliconFlowModel"
    static let whisperModel = "whisperModel"
    static let transcriptionLanguage = "transcriptionLanguage"
    static let expectedSpeakers = "expectedSpeakers"
    static let meetingMode = "meetingMode"
}
