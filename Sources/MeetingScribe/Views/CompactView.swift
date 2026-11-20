import SwiftUI

/// B: compact main window (design mockup plan B, 548pt — the capsule's
/// expanded state). The same transcript-first layout as the main
/// window, in a smaller titled window: mode picker, transport, timer,
/// dual-channel spectrum, transcript list, live-partial footer and
/// summary. The transcript pieces are the shared views from
/// TranscriptViews.swift, so both windows behave identically.
struct CompactView: View {
    @EnvironmentObject var session: MeetingSession
    @AppStorage(SettingsKey.meetingMode) private var modeRaw = MeetingMode.online.rawValue
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if session.isRecording {
                SpectrumStrip(
                    micBars: session.micSpectrum,
                    systemBars: session.systemSpectrum,
                    showSystem: session.mode == .online
                )
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            Divider()
            TranscriptListView()
            LivePartialFooterView()
            Divider()
            SummarySectionView()
        }
        .frame(minWidth: 520, minHeight: 420)
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .onAppear {
            session.mode = MeetingMode(rawValue: modeRaw) ?? .online
        }
        .onChange(of: modeRaw) { _, newValue in
            session.mode = MeetingMode(rawValue: newValue) ?? .online
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Picker("模式", selection: $modeRaw) {
                ForEach(MeetingMode.allCases) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .disabled(session.isRecording)

            TransportControls(size: 28)

            if session.isRecording {
                RecordingIndicator(elapsed: session.elapsedSeconds, paused: session.isPaused)
            } else {
                Text(session.status)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            ViewModeMenu(current: .compact)

            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .help("设置")
        }
        .padding()
    }
}
