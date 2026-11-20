import SwiftUI

struct ContentView: View {
    /// Owned by the app and shared with the mini window.
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
        .frame(minWidth: 720, minHeight: 540)
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .onAppear {
            session.mode = MeetingMode(rawValue: modeRaw) ?? .online
        }
        .onChange(of: modeRaw) { _, newValue in
            session.mode = MeetingMode(rawValue: newValue) ?? .online
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker("模式", selection: $modeRaw) {
                ForEach(MeetingMode.allCases) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .disabled(session.isRecording)

            TransportControls()

            if session.isRecording {
                RecordingIndicator(elapsed: session.elapsedSeconds, paused: session.isPaused)
            } else {
                Text(session.status)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Mode switch, not a second window: the menu opens the
            // chosen mode's window and dismisses this one, so only
            // one view is ever visible.
            ViewModeMenu(current: .main)

            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .help("设置")
        }
        .padding()
    }
}
