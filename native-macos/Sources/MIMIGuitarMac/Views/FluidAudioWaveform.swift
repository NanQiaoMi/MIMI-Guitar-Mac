import SwiftUI

/// Replicates the web version's FluidAudioWaveform (Canvas 2D Dual-layer Sine/Cosine Waves).
/// Smoothly undulating fluid sound waves driven by audio playback state and BPM.
struct MIMIFluidAudioWaveform: View {
    let isPlaying: Bool
    let bpm: Double
    var primaryColor: Color = MIMITheme.ink
    var secondaryColor: Color = MIMITheme.signalBlue
    var width: CGFloat = 105
    var height: CGFloat = 26

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                guard w > 0, h > 0 else { return }

                let midY = h / 2.0
                let now = timeline.date.timeIntervalSinceReferenceDate

                // Tempo factor drives undulating phase speed
                let effectiveBpm = bpm > 0 ? bpm : 72.0
                let tempoFactor = min(2.8, max(0.4, effectiveBpm / 72.0))

                // Phase progression
                let speed = 2.7 * tempoFactor // Continuous angular speed
                let phase1 = now * speed
                let phase2 = now * speed * 0.73

                // Amplitude target: 36% of height when playing, 0 when paused
                let amp = isPlaying ? (h * 0.36) : 0.0

                // 1. Subtle datum baseline underneath
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: midY))
                baseline.addLine(to: CGPoint(x: w, y: midY))
                context.stroke(
                    baseline,
                    with: .color(primaryColor.opacity(0.12)),
                    lineWidth: 1.0
                )

                if amp > 0.001 {
                    let k1 = (2.0 * .pi) / (w * 0.46)
                    let k2 = (2.0 * .pi) / (w * 0.88)
                    let k3 = (2.0 * .pi) / (w * 0.62)
                    let k4 = (2.0 * .pi) / (w * 0.34)
                    let step: CGFloat = 2.0

                    // 2. Layer 2: Secondary Harmonic Wave (Fluid Counter-Wave, Signal Blue)
                    var wave2Path = Path()
                    var x: CGFloat = 0
                    while x <= w {
                        let normX = x / w
                        let envelope = sin(normX * .pi)
                        let waveVal = cos(x * k3 - phase1 * 1.2) * 0.65 + sin(x * k4 + phase2 * 1.1) * 0.35
                        let y = midY + waveVal * envelope * (amp * 0.72)
                        if x == 0 {
                            wave2Path.move(to: CGPoint(x: x, y: y))
                        } else {
                            wave2Path.addLine(to: CGPoint(x: x, y: y))
                        }
                        x += step
                    }
                    context.stroke(
                        wave2Path,
                        with: .color(secondaryColor.opacity(0.45)),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                    )

                    // 3. Layer 1: Primary Fluid Sine/Cosine Wave (Ink)
                    var wave1Path = Path()
                    x = 0
                    while x <= w {
                        let normX = x / w
                        let envelope = sin(normX * .pi)
                        let waveVal = sin(x * k1 + phase1) * 0.72 + cos(x * k2 - phase2 * 0.85) * 0.28
                        let y = midY + waveVal * envelope * amp
                        if x == 0 {
                            wave1Path.move(to: CGPoint(x: x, y: y))
                        } else {
                            wave1Path.addLine(to: CGPoint(x: x, y: y))
                        }
                        x += step
                    }
                    context.stroke(
                        wave1Path,
                        with: .color(primaryColor.opacity(0.92)),
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .accessibilityHidden(true)
    }
}
