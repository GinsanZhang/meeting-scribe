import SwiftUI

/// A row of vertical bars driven by 0...1 levels. Heights animate
/// between updates so the ~4 Hz chunk rate still looks smooth.
struct SpectrumBarsView: View {
    let bars: [CGFloat]
    let color: Color
    var height: CGFloat = 24
    var barWidth: CGFloat = 3

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(bars.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(color)
                    .frame(width: barWidth, height: max(2, bars[i] * height))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.15), value: bars)
    }
}

/// Slim dual-channel spectrum strip for the main window. Shown while
/// recording; in-person mode shows only the mic lane.
struct SpectrumStrip: View {
    let micBars: [CGFloat]
    let systemBars: [CGFloat]
    let showSystem: Bool
    var height: CGFloat = 18
    var barWidth: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            spectrumLane(label: "MIC", bars: micBars, color: .cyan)
            if showSystem {
                spectrumLane(label: "SYS", bars: systemBars, color: .orange)
            }
        }
    }

    private func spectrumLane(label: String, bars: [CGFloat], color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .leading)
            SpectrumBarsView(bars: bars, color: color, height: height, barWidth: barWidth)
        }
    }
}
