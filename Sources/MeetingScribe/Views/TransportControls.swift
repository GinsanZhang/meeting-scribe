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

/// Round recorder-style transport shared by the main window, the
/// floating capsule and the compact window: a red record circle,
/// pause/resume, and stop. The record circle doubles as the resume
/// control while paused (it is the obvious "start again" button);
/// Cmd+R starts when idle and resumes when paused.
///
/// The mini window does NOT use this — its mic is the only control
/// (tap = start / pause / resume, long-press = stop).
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
            }
            .buttonStyle(.plain)
            .disabled(session.isRecording && !session.isPaused)
            .opacity(session.isRecording && !session.isPaused ? 0.35 : 1)
            .keyboardShortcut("r", modifiers: .command)
            .help(session.isPaused ? "继续录音" : "开始录音")

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

            Button(action: { session.stop() }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13))
                    .frame(width: size - 2, height: size - 2)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .disabled(!session.isRecording)
            .help("结束录音")
        }
    }
}
