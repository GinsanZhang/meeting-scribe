import SwiftUI

/// C: top floating bar (design mockup plan C). One thin strip docked
/// at the top center of the screen, floating above other apps while
/// a meeting runs: status + timer, a compact dual-channel spectrum,
/// one scrolling live line, and mini transport controls. Drag it by
/// its background to move it; the menu switches to any other mode.
struct TopBarView: View {
    @EnvironmentObject var session: MeetingSession
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        HStack(spacing: 10) {
            RecordingStatusView()

            if session.isRecording {
                SpectrumStrip(
                    micBars: session.micSpectrum,
                    systemBars: session.systemSpectrum,
                    showSystem: session.mode == .online,
                    height: 10,
                    barWidth: 2
                )
            }

            Text(liveText)
                .font(.system(size: 13))
                .foregroundStyle(liveTextIsHint ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.3), value: liveText)

            Spacer(minLength: 0)

            TransportControls(size: 24)

            ViewModeMenu(current: .topBar)

            Button(action: {
                openWindow(id: ViewMode.main.rawValue)
                dismissWindow(id: ViewMode.topBar.rawValue)
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("返回主窗口")
        }
        .padding(.horizontal, 12)
        .frame(width: 720, height: 44)
        .background(BorderlessWindowConfigurator(
            level: .floating,
            dockAtTopCenter: true,
            dockWidth: 720,
            dockHeight: 44
        ))
    }

    /// The in-progress partial while speaking, else the latest
    /// finalized segment, else a status hint.
    private var liveText: String {
        if !session.liveMicPartial.isEmpty { return session.liveMicPartial }
        if let last = session.segments.last { return last.text }
        return session.isRecording ? "正在聆听…" : session.status
    }

    private var liveTextIsHint: Bool {
        session.liveMicPartial.isEmpty && session.segments.isEmpty
    }
}
