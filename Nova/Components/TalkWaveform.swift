import SwiftUI

// The six bars from the login mark, grown up and alive. They follow his voice while listening,
// sweep while Nova works, and move with her voice while she speaks.
struct TalkWaveform: View {
    let phase: TalkSession.Phase
    // Read once per frame rather than published, because it changes faster than SwiftUI should diff
    let level: () -> Float

    // Same proportions as the app icon and the login mark
    private let ratios: [CGFloat] = [0.40, 0.70, 1.00, 0.85, 0.60, 0.45]
    private let maxHeight: CGFloat = 180
    private let minHeight: CGFloat = 14

    // Raw loudness jumps every buffer; bars that followed it exactly would flicker
    @State private var smoothed = Smoother()

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let loudness = smoothed.next(CGFloat(level()))

            HStack(alignment: .center, spacing: 12) {
                ForEach(ratios.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 6)
                        .frame(width: 16, height: height(bar: i, time: time, loudness: loudness))
                        .foregroundColor(Theme.accent.opacity(phase == .stopped ? 0.35 : 1))
                        .shadow(color: Theme.accentGlow, radius: 10 + 18 * loudness)
                }
            }
            .frame(height: maxHeight)
        }
        .accessibilityHidden(true)
    }

    private func height(bar i: Int, time: TimeInterval, loudness: CGFloat) -> CGFloat {
        let ratio = ratios[i]
        let wobble = CGFloat(sin(time * 9 + Double(i) * 1.7))
        let fraction: CGFloat

        switch phase {
        case .listening:
            // A slow breath so the bars are alive in a silent room, lifted by his voice
            let breath = 0.22 + 0.08 * CGFloat(sin(time * 2 + Double(i) * 0.5))
            fraction = ratio * (breath + 0.78 * loudness * (1 + 0.15 * wobble))
        case .speaking:
            fraction = ratio * (0.18 + 0.82 * loudness * (1 + 0.2 * wobble))
        case .thinking, .starting:
            // A wave travelling left to right, the working state with no sound to follow
            let wave = (1 + CGFloat(sin(time * 4 - Double(i) * 0.7))) / 2
            fraction = 0.18 + 0.4 * wave
        case .stopped:
            fraction = ratio * 0.25
        }
        return max(minHeight, maxHeight * min(fraction, 1))
    }
}

// Rises fast and falls slowly, the way a level meter reads naturally
private final class Smoother {
    private var value: CGFloat = 0

    func next(_ target: CGFloat) -> CGFloat {
        let rate: CGFloat = target > value ? 0.45 : 0.12
        value += (target - value) * rate
        return value
    }
}
