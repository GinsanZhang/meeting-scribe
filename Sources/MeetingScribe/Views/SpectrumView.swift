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
        .animation(.easeOut(duration: 0.25), value: bars)
    }
}

/// Slim dual-channel spectrum strip for the main window. Shown while
/// recording; in-person mode shows only the mic lane.
struct SpectrumStrip: View {
    let micBars: [CGFloat]
    let systemBars: [CGFloat]
    let showSystem: Bool

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
            SpectrumBarsView(bars: bars, color: color, height: 18)
        }
    }
}

/// Radial spectrum for the mini window: bars radiate around the mic.
/// A TimelineView shimmer keeps the motion smooth between the ~4 Hz
/// bar updates (the bars themselves are level-driven, not an FFT).
struct RadialSpectrumView: View {
    let bars: [CGFloat]
    let color: Color
    var diameter: CGFloat = 150

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let now = timeline.date.timeIntervalSinceReferenceDate
                let innerRadius = diameter * 0.30
                for (i, value) in bars.enumerated() {
                    let angle = Double(i) / Double(max(bars.count, 1)) * 2 * .pi - .pi / 2
                    let dx = CGFloat(cos(angle))
                    let dy = CGFloat(sin(angle))
                    // Gentle per-bar shimmer so the ring stays alive
                    // between bar updates; scaled by the real level.
                    let wobble = 0.85 + 0.15 * sin(now * 6 + Double(i) * 0.7)
                    let length = max(0, CGFloat(value) * CGFloat(wobble)) * diameter * 0.16
                    let start = CGPoint(
                        x: center.x + dx * innerRadius,
                        y: center.y + dy * innerRadius
                    )
                    let end = CGPoint(
                        x: center.x + dx * (innerRadius + length),
                        y: center.y + dy * (innerRadius + length)
                    )
                    var path = Path()
                    path.move(to: start)
                    path.addLine(to: end)
                    context.stroke(
                        path,
                        with: .color(color.opacity(0.35 + 0.65 * Double(value))),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                }
            }
            .frame(width: diameter, height: diameter)
        }
    }
}
