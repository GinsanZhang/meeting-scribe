import SwiftUI

@main
struct MeetingScribeApp: App {
    /// One session shared by all three view-mode windows, so
    /// recording, pausing and the transcript stay in sync between them.
    @StateObject private var session = MeetingSession()
    @AppStorage(SettingsKey.appearance) private var appearanceRaw = Appearance.system.rawValue

    private var colorScheme: ColorScheme? {
        Appearance(rawValue: appearanceRaw)?.colorScheme
    }

    var body: some Scene {
        // The main window is a single Window (id "main"), not a
        // WindowGroup: switching to a floating mode dismisses it
        // and opens the other window, so only one view is ever on
        // screen.
        Window("MeetingScribe", id: "main") {
            ContentView()
                .environmentObject(session)
                .preferredColorScheme(colorScheme)
        }
        .defaultSize(width: 1100, height: 700)
        // Floating capsule (560pt) — spectrum + one live line +
        // transport, borderless and floating above other apps.
        // Always dark: the capsule's design is a dark pill on any
        // desktop, in either app theme.
        Window("MeetingScribe 悬浮胶囊", id: ViewMode.capsule.rawValue) {
            CapsuleView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 560, height: 64)
        // Top floating bar — one thin strip docked at the top
        // center of the screen, floating above other apps.
        // Always light: the bar's design is a white strip on any
        // desktop, in either app theme.
        Window("MeetingScribe 顶部悬浮条", id: ViewMode.topBar.rawValue) {
            TopBarView()
                .environmentObject(session)
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1200, height: 48)
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
