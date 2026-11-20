import SwiftUI

/// The five view modes of the app. Exactly one window is visible at
/// a time: switching opens the target window and dismisses the
/// current one, so the modes never stack on screen together.
///
/// The raw value is the Window scene id in MeetingScribeApp, so
/// `openWindow(id: mode.rawValue)` / `dismissWindow(id: mode.rawValue)`
/// are the whole switching mechanism.
enum ViewMode: String, CaseIterable, Identifiable {
    /// The full main window (ContentView).
    case main
    /// A: floating capsule — spectrum + one live line + transport.
    case capsule
    /// B: compact main window — the transcript in a smaller window.
    case compact
    /// C: top floating bar — one thin strip docked at the top of the screen.
    case topBar
    /// D: minimal offline window — the mic is the only control.
    case mini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .main: return "主窗口"
        case .capsule: return "悬浮胶囊"
        case .compact: return "精简主窗"
        case .topBar: return "顶部悬浮条"
        case .mini: return "极简"
        }
    }

    var icon: String {
        switch self {
        case .main: return "macwindow"
        case .capsule: return "capsule"
        case .compact: return "rectangle.compress.vertical"
        case .topBar: return "menubar.rectangle"
        case .mini: return "mic.circle"
        }
    }
}

/// A menu that switches to any other view mode. Put it in every
/// window's header so the user can jump between modes from anywhere.
/// The current mode is disabled in the list.
struct ViewModeMenu: View {
    let current: ViewMode

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Menu {
            ForEach(ViewMode.allCases) { mode in
                Button {
                    switchTo(mode)
                } label: {
                    Label(mode.displayName, systemImage: mode.icon)
                }
                .disabled(mode == current)
            }
        } label: {
            Image(systemName: "rectangle.on.rectangle")
        }
        .help("切换视图")
    }

    private func switchTo(_ mode: ViewMode) {
        guard mode != current else { return }
        // Open first, then dismiss, so a view is always visible.
        openWindow(id: mode.rawValue)
        dismissWindow(id: current.rawValue)
    }
}
