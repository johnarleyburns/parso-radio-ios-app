import SwiftUI

// Shown as the screen backdrop when a track has no artwork. A calm,
// GPU-light procedural "now playing" visualizer: drifting soft colour orbs
// + slow pulsing concentric rings. The palette is derived deterministically
// from a per-track seed, so every track gets a visibly distinct look (and
// the image always changes when the track changes — never a stale picture).
struct ProceduralVisualizerView: View {
    let seed: String

    // Stable djb2 hash → [0,1) base hue (NOT String.hashValue, which is
    // process-randomised and would differ every launch).
    static func hue(for seed: String) -> Double {
        let h = seed.utf8.reduce(UInt64(5381)) { ($0 &<< 5) &+ $0 &+ UInt64($1) }
        return Double(h % 1000) / 1000.0
    }

    private var baseHue: Double { Self.hue(for: seed) }

    var body: some View {
        let h = baseHue
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let maxD = max(size.width, size.height)
                let minD = min(size.width, size.height)

                // Dark tinted base.
                gc.fill(Path(CGRect(origin: .zero, size: size)),
                        with: .color(Color(hue: h, saturation: 0.55, brightness: 0.12)))

                // Three drifting radial-gradient orbs (Lissajous paths).
                for i in 0..<3 {
                    let hue = (h + Double(i) / 3.0 * 0.34)
                        .truncatingRemainder(dividingBy: 1.0)
                    let ph = Double(i) * 2.1
                    let cx = size.width  * (0.5 + 0.33 * sin(t * 0.13 + ph))
                    let cy = size.height * (0.5 + 0.33 * cos(t * 0.11 + ph * 1.3))
                    let r  = maxD * (0.42 + 0.06 * sin(t * 0.4 + ph))
                    let rect = CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)
                    let grad = Gradient(colors: [
                        Color(hue: hue, saturation: 0.75, brightness: 0.9).opacity(0.55),
                        .clear,
                    ])
                    gc.fill(
                        Path(ellipseIn: rect),
                        with: .radialGradient(grad,
                                              center: CGPoint(x: cx, y: cy),
                                              startRadius: 0, endRadius: r))
                }

                // Slow pulsing concentric rings — the "audio" motif.
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for k in 0..<5 {
                    let pulse = (sin(t * 1.05 + Double(k) * 0.85) + 1) / 2
                    let rr = (Double(k) / 5.0 + 0.10) * Double(minD)
                        * (0.92 + 0.16 * pulse)
                    let ring = Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr,
                                                      width: 2 * rr, height: 2 * rr))
                    gc.stroke(ring,
                              with: .color(Color(hue: h, saturation: 0.25,
                                                  brightness: 1.0)
                                  .opacity(0.05 + 0.05 * pulse)),
                              lineWidth: 1.5)
                }
            }
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }
}
