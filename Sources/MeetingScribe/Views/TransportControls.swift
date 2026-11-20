import SwiftUI

/// Recording indicator: pulsing red dot + elapsed time (paused time
/// excluded; the session ticks it once a second). Amber and still
/// while paused. Only exists while actually recording.
struct RecordingIndicator: View {
    let elapsed: TimeInterval
    let paused: Bool

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(paused ? Color.orange : Color.red)
                .frame(width: 8, height: 8)
                .scaleEffect(paused ? 1 : (pulse ? 1.3 : 1))
                .opacity(paused ? 1 : (pulse ? 0.55 : 1))
                .animation(
                    paused ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: pulse
                )
                .onAppear { pulse = true }
            Text(formatTime(elapsed))
                .font(.callout.monospacedDigit())
            if paused {
                Text("已暂停")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

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

/// Round recorder-style transport shared by the main window: a red
/// record circle and pause/resume. The record circle is the primary
/// action — start when idle, stop while recording, resume while
/// paused (it is the obvious "start again" button); its icon shows
/// a white square while recording and a white dot otherwise.
/// Cmd+R fires the same primary action.
///
/// The floating capsule and top bar do NOT use this — they have
/// their own transport (the capsule's red square, the bar's
/// stop/pause buttons).
struct TransportControls: View {
    @EnvironmentObject var session: MeetingSession

    /// Diameter of the red record circle; the other two buttons are
    /// 2pt smaller. Default matches the main window.
    var size: CGFloat = 32

    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                if session.isPaused {
                    session.resume()
                } else if session.isRecording {
                    session.stop()
                } else {
                    session.start()
                }
            }) {
                Circle()
                    .fill(Color.red)
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.red.opacity(0.35), lineWidth: 3)
                    )
                    .overlay(
                        Group {
                            if session.isRecording && !session.isPaused {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white)
                                    .frame(width: 10, height: 10)
                            } else {
                                Circle().fill(Color.white).frame(width: 10, height: 10)
                            }
                        }
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: .command)
            .help(session.isPaused ? "继续录音" : session.isRecording ? "结束录音" : "开始录音")

            Button(action: {
                if session.isPaused { session.resume() } else { session.pause() }
            }) {
                Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 13))
                    .frame(width: size - 2, height: size - 2)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .disabled(!session.isRecording)
            .help(session.isPaused ? "继续录音" : "暂停录音")
        }
    }
}
