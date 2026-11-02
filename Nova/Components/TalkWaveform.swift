import SwiftUI

// The six bars from the login mark, grown up and alive, inside rings that orbit them. They follow
// his voice while listening, sweep while Nova works, and move with her voice while she speaks.
// Everything takes the colour of what Nova is doing (see Phase.color below), so the state can be
// read from across the room.
struct TalkWaveform: View {
    let phase: TalkSession.Phase
    // Read once per frame rather than published, because it changes faster than SwiftUI should diff
    let level: () -> Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Same proportions as the app icon and the login mark
    private let ratios: [CGFloat] = [0.40, 0.70, 1.00, 0.85, 0.60, 0.45]
    private let maxHeight: CGFloat = 120
    private let minHeight: CGFloat = 10
    private let ringSize: CGFloat = 250

    // One lap of the orbiting arc takes this long
    private let lapSeconds: Double = 9

    // Raw loudness jumps every buffer; bars that followed it exactly would flicker
    @State private var smoothed = Smoother()

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let loudness = smoothed.next(CGFloat(level()))
            let color = phase.color

            ZStack {
                rings(color: color, angle: orbitAngle(time))

                HStack(alignment: .center, spacing: 9) {
                    ForEach(ratios.indices, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .frame(width: 11, height: height(bar: i, time: time, loudness: loudness))
                            .foregroundColor(color)
                            .shadow(color: color.opacity(0.5), radius: 6 + 14 * loudness)
                    }
                }
            }
            .frame(width: ringSize, height: ringSize)
            // The colour eases from one state to the next instead of snapping
            .animation(.easeInOut(duration: 0.35), value: phase)
        }
        .accessibilityHidden(true)
    }

    // MARK: Rings

    private func rings(color: Color, angle: Double) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: 1)

            Circle()
                .inset(by: 22)
                .stroke(color.opacity(0.34), style: StrokeStyle(lineWidth: 1, dash: [1, 6]))

            if phase != .stopped {
                arc(color: color)
                    .rotationEffect(.degrees(angle))

                // A second arc while she works, so thinking looks busier than listening even
                // in a glance from across the room
                if phase == .thinking || phase == .starting {
                    arc(color: color)
                        .rotationEffect(.degrees(angle + 180))
                }
            }
        }
    }

    // A quarter of the outer ring, drawn bright
    private func arc(color: Color) -> some View {
        Circle()
            .trim(from: 0, to: 0.25)
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .shadow(color: color.opacity(0.6), radius: 6)
    }

    // Where the arc is now. Taken modulo one lap, because the clock counts seconds since 2001 and
    // a number that large loses the precision a smooth rotation needs
    private func orbitAngle(_ time: TimeInterval) -> Double {
        guard !reduceMotion else { return 0 }
        return time.truncatingRemainder(dividingBy: lapSeconds) / lapSeconds * 360
    }

    // MARK: Bars

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
        case .waiting, .stopped:
            fraction = ratio * 0.25
        }
        return max(minHeight, maxHeight * min(fraction, 1))
    }
}

extension TalkSession.Phase {
    // The colour that means this state, here and anywhere else the app shows what Nova is doing.
    // Waiting for his tap is blue, because she is ready to listen.
    var color: Color {
        switch self {
        case .listening, .waiting: return Theme.listening
        case .starting, .thinking: return Theme.thinking
        case .speaking:            return Theme.speaking
        case .stopped:             return Theme.textSecondary
        }
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
