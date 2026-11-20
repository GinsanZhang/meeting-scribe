import SwiftUI

/// The three view modes of the app (design 方案 B + 悬浮转录): the
/// workbench main window, the floating capsule and the top floating
/// bar. Exactly one window is visible at a time: switching opens the
/// target window and dismisses the current one, so the modes never
/// stack on screen together.
///
/// The raw value is the Window scene id in MeetingScribeApp, so
/// `openWindow(id: mode.rawValue)` / `dismissWindow(id: mode.rawValue)`
/// are the whole switching mechanism.
enum ViewMode: String, CaseIterable, Identifiable {
    /// The workbench main window (ContentView).
    case main
    /// Floating capsule — spectrum + one live line + transport.
    case capsule
    /// Top floating bar — one thin strip docked at the top of the screen.
    case topBar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .main: return "主窗口"
        case .capsule: return "悬浮胶囊"
        case .topBar: return "顶部悬浮条"
        }
    }

    var icon: String {
        switch self {
        case .main: return "macwindow"
        case .capsule: return "capsule"
        case .topBar: return "menubar.rectangle"
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
        .menuStyle(.borderlessButton)
        .help("切换视图")
    }

    private func switchTo(_ mode: ViewMode) {
        guard mode != current else { return }
        // Open first, then dismiss, so a view is always visible.
        openWindow(id: mode.rawValue)
        dismissWindow(id: current.rawValue)
    }
}
