import SwiftUI

@main
struct MeetingScribeApp: App {
    /// One session shared by the main window and the mini window, so
    /// recording, pausing and the transcript stay in sync between them.
    @StateObject private var session = MeetingSession()
    @AppStorage(SettingsKey.appearance) private var appearanceRaw = Appearance.system.rawValue

    private var colorScheme: ColorScheme? {
        Appearance(rawValue: appearanceRaw)?.colorScheme
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .preferredColorScheme(colorScheme)
        }
        // Minimal mode (design mockup plan D): borderless, transparent,
        // single-button transport. Opened from the main window; the
        // window itself is made borderless by MiniView's configurator.
        Window("MeetingScribe 极简", id: "mini") {
            MiniView()
                .environmentObject(session)
                .preferredColorScheme(colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 250, height: 250)
    }
}

/// App appearance: follow the system, or force dark / light.
/// Applied at the scene level so both windows switch together.
enum Appearance: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .dark: return "深色"
        case .light: return "浅色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}
