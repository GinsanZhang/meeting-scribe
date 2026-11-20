import SwiftUI

/// Status dot + elapsed time (mm:ss), shared by the floating capsule
/// and the top bar. Red and pulsing while recording, amber and still
/// while paused, grey when idle.
struct RecordingStatusView: View {
    @EnvironmentObject var session: MeetingSession

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(session.isRecording ? (session.isPaused ? .orange : .red) : .secondary)
                .frame(width: 7, height: 7)
                .scaleEffect(session.isRecording && !session.isPaused && pulse ? 1.3 : 1)
                .opacity(session.isRecording && !session.isPaused && pulse ? 0.55 : 1)
                .animation(
                    session.isRecording && !session.isPaused
                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : nil,
                    value: pulse
                )
                .onAppear { pulse = true }
            Text(formatTime(session.elapsedSeconds))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            if session.isPaused {
                Text("已暂停")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A: floating capsule (design mockup plan A, 372pt). A small
/// borderless transparent window that floats above other apps while
/// a meeting runs: status + timer, dual-channel spectrum, one live
/// subtitle line, and the round three-key transport. No transcript
/// list — for watching the meeting, not reading it.
struct CapsuleView: View {
    @EnvironmentObject var session: MeetingSession
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                RecordingStatusView()
                Text("\(session.mode.displayName) · \(session.engineBadge)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                ViewModeMenu(current: .capsule)
                Button(action: {
                    openWindow(id: ViewMode.main.rawValue)
                    dismissWindow(id: ViewMode.capsule.rawValue)
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("返回主窗口")
            }

            if session.isRecording {
                SpectrumStrip(
                    micBars: session.micSpectrum,
                    systemBars: session.systemSpectrum,
                    showSystem: session.mode == .online
                )
            }

            liveLine

            TransportControls(size: 28)
        }
        .padding(12)
        .frame(width: 372)
        .background(BorderlessWindowConfigurator(level: .floating))
    }

    /// One live line: the in-progress partial while speaking, else the
    /// latest finalized segment, else a hint. Fades between lines.
    private var liveLine: some View {
        let text = !session.liveMicPartial.isEmpty
            ? session.liveMicPartial
            : (session.segments.last?.text ?? "")
        return Text(text.isEmpty
            ? (session.isRecording ? "正在聆听…" : "开始录音后，识别的文字会出现在这里")
            : text)
            .font(.system(size: 13))
            .foregroundStyle(text.isEmpty ? .secondary : .primary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.3), value: text)
    }
}
