import AppKit
import SwiftUI

/// Minimal mode (design mockup plan D): a small borderless transparent
/// window for in-person meetings. The mic itself is the only transport
/// control (tap = start / pause / resume, long-press = stop); the
/// spectrum is a ring around the mic and the live text scrolls as a
/// frosted subtitle band with the middle line in focus.
///
/// RED LINE (from the 2026-11-19 crash fix): live subtitles must stay
/// outside the List in a fixed footer. This window has no List at all,
/// so the rule holds by construction.
struct MiniView: View {
    @EnvironmentObject var session: MeetingSession
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var holdProgress = 0.0
    /// Set when a long-press stops the recording, so the Button action
    /// that fires on release doesn't immediately start a new one.
    @State private var suppressTap = false

    var body: some View {
        VStack(spacing: 8) {
            topCapsules
            micButton
            hintText
            subtitleBand
        }
        .padding(10)
        .frame(width: 250)
        .background(WindowConfigurator())
    }

    // MARK: - Top capsules

    private var topCapsules: some View {
        HStack(spacing: 6) {
            capsule {
                HStack(spacing: 5) {
                    Circle()
                        .fill(session.isRecording ? (session.isPaused ? .orange : .red) : .secondary)
                        .frame(width: 6, height: 6)
                    Text(formatTime(session.elapsedSeconds))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
            }
            capsule {
                Text("\(session.mode.displayName) · \(session.engineBadge)")
                    .font(.system(size: 11))
            }
            Spacer(minLength: 0)
            ViewModeMenu(current: .mini)
            // Switch back to the main window: reopen it first, then
            // dismiss the mini window, so a view is always visible.
            Button(action: {
                openWindow(id: "main")
                dismissWindow(id: "mini")
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("返回主窗口")
        }
    }

    private func capsule<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Mic button (the only transport control)

    private var micButton: some View {
        ZStack {
            RadialSpectrumView(
                bars: session.micSpectrum,
                color: session.isRecording && !session.isPaused ? .cyan : .gray,
                diameter: 148
            )
            // A plain Button for the tap (start / pause / resume) plus
            // a built-in long-press for stop. The old hand-rolled
            // DragGesture state machine could get stuck: a press whose
            // release never arrived (e.g. the window's drag-to-move
            // stealing the gesture) left the button dead. The Button's
            // click gesture has no such state to get stuck in.
            Button(action: micTap) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 64, height: 64)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    session.isRecording ? Color.red : Color.primary.opacity(0.2),
                                    lineWidth: 2
                                )
                        )
                    Image(systemName: session.isRecording && session.isPaused ? "play.fill" : "mic.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(session.isRecording ? .red : .primary)
                }
            }
            .buttonStyle(.plain)
            .onLongPressGesture(
                minimumDuration: 0.55,
                pressing: { pressing in
                    if pressing {
                        withAnimation(.linear(duration: 0.55)) { holdProgress = 1 }
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 }
                    }
                },
                perform: {
                    suppressTap = true
                    if session.isRecording { session.stop() }
                }
            )
            // Long-press progress ring (fills over 0.55 s).
            Circle()
                .trim(from: 0, to: holdProgress)
                .stroke(Color.red, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 72, height: 72)
                .rotationEffect(.degrees(-90))
                .allowsHitTesting(false)
        }
        .frame(width: 148, height: 148)
    }

    /// Tap: start, pause, or resume. A tap that follows a long-press
    /// is swallowed: the Button action also fires on release after a
    /// long-press stop, and without the guard it would immediately
    /// start a new recording.
    private func micTap() {
        if suppressTap {
            suppressTap = false
            return
        }
        if session.isRecording {
            if session.isPaused { session.resume() } else { session.pause() }
        } else {
            session.start()
        }
    }

    private var hintText: some View {
        Text(hint)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    private var hint: String {
        if session.isRecording {
            session.isPaused ? "已暂停 · 点按继续 · 长按结束" : "点按暂停 · 长按结束"
        } else {
            "点按开始"
        }
    }

    // MARK: - Rolling subtitle band

    private struct SubtitleRow: Identifiable {
        let id: String
        let text: String
        let focus: Bool
        let far: Bool
    }

    /// Last three texts: the two most recent finalized segments plus the
    /// live partial. The middle row is sharp; the outer rows blur and
    /// fade, like subtitles scrolling. The live partial keeps a stable
    /// "current" id so word-by-word growth doesn't re-animate the row.
    private var subtitleRows: [SubtitleRow] {
        let finalized = session.segments.suffix(2).map(\.text)
        var rows: [SubtitleRow] = []
        for (index, text) in finalized.enumerated() {
            rows.append(SubtitleRow(id: text, text: text, focus: false, far: index == 0))
        }
        if !session.liveMicPartial.isEmpty {
            rows.append(SubtitleRow(
                id: "current", text: session.liveMicPartial, focus: false, far: false
            ))
        }
        let recent = Array(rows.suffix(3))
        guard !recent.isEmpty else { return [] }
        // The middle row is the focus; with fewer rows the last one is.
        var focused = recent
        let focusIndex = recent.count == 3 ? 1 : recent.count - 1
        focused[focusIndex].focus = true
        return focused
    }

    private var subtitleSignature: String {
        subtitleRows.map(\.text).joined(separator: "\n")
    }

    private var subtitleBand: some View {
        VStack(spacing: 2) {
            if subtitleRows.isEmpty {
                Text(session.isRecording ? "正在聆听…" : "开始录音后，识别的文字会出现在这里")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                ForEach(subtitleRows) { row in
                    Text(row.text)
                        .font(.system(size: 12, weight: row.focus ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .blur(radius: row.focus ? 0 : (row.far ? 2.8 : 1.4))
                        .opacity(row.focus ? 1 : (row.far ? 0.25 : 0.55))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .animation(.easeInOut(duration: 0.5), value: subtitleSignature)
        .mask(
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.25),
                    .init(color: .black, location: 0.75),
                    .init(color: .clear, location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Makes the mini window borderless and transparent: no title bar, no
/// window background — only the frosted capsules float on the desktop.
/// Applied as a background view so it can reach its NSWindow; if the
/// window isn't reachable yet, the async dispatch retries on the next
/// run loop tick. If anything here fails, the window just keeps its
/// title bar and still works.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.remove(.titled)
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
