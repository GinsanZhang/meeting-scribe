import SwiftUI

@main
struct MeetingScribeApp: App {
    /// One session shared by all five view-mode windows, so
    /// recording, pausing and the transcript stay in sync between them.
    @StateObject private var session = MeetingSession()
    @AppStorage(SettingsKey.appearance) private var appearanceRaw = Appearance.system.rawValue

    private var colorScheme: ColorScheme? {
        Appearance(rawValue: appearanceRaw)?.colorScheme
    }

    var body: some Scene {
        // The main window is a single Window (id "main"), not a
        // WindowGroup: the mini window is a mode switch for it, and
        // switching dismisses one window while opening the other,
        // so only one view is ever on screen.
        Window("MeetingScribe", id: "main") {
            ContentView()
                .environmentObject(session)
                .preferredColorScheme(colorScheme)
        }
        .defaultSize(width: 720, height: 540)
        // A: floating capsule (372pt) — spectrum + one live line +
        // transport, borderless and floating above other apps.
        Window("MeetingScribe 悬浮胶囊", id: ViewMode.capsule.rawValue) {
            CapsuleView()
                .environmentObject(session)
                .preferredColorScheme(colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 372, height: 220)
        // B: compact main window (548pt) — the transcript in a
        // smaller titled window.
        Window("MeetingScribe 精简", id: ViewMode.compact.rawValue) {
            CompactView()
                .environmentObject(session)
                .preferredColorScheme(colorScheme)
        }
        .defaultSize(width: 548, height: 480)
        // C: top floating bar — one thin strip docked at the top
        // center of the screen, floating above other apps.
        Window("MeetingScribe 顶部悬浮条", id: ViewMode.topBar.rawValue) {
            TopBarView()
                .environmentObject(session)
                .preferredColorScheme(colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 720, height: 44)
        // Minimal mode (design mockup plan D): borderless, transparent,
        // single-button transport. Switching to it dismisses the main
        // window; closing it reopens the main window. The window
        // itself is made borderless by MiniView's configurator.
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
/// Applied at the scene level so all windows switch together.
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
