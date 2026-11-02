import SwiftUI

// Nova working on a reply: a purple ring on the thread, breathing, with what she is doing beside
// it. Sits on the same line as the messages (ThreadRow), so the answer arrives where the ring was.
//
// TimelineView drives both the breathing and the clock, so there is no Timer to clean up.
// The previous Timer was never invalidated and kept firing after the indicator disappeared.
struct NovaTypingIndicator: View {
    let startedAt: Date
    // "Checking your calendar" while a tool runs, nil while Nova is only thinking
    var stage: String? = nil

    // A quick reply should never flash a clock; only a turn slow enough to feel stuck shows one
    private let clockDelay: TimeInterval = 3

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 0.6)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            let bright = Int(elapsed / 0.6) % 2 == 0

            ThreadRow(nodeTop: 8) {
                RingNode(color: Theme.thinking)
                    .opacity(bright ? 1 : 0.45)
                    .animation(.easeInOut(duration: 0.6), value: bright)
            } content: {
                Text(label(elapsed: elapsed))
                    .novaFont(10, weight: .medium, design: .monospaced)
                    .monospacedDigit()
                    .foregroundColor(Theme.thinking)
                    .tracking(2)
                    .padding(.top, 1)
            }
        }
    }

    private func label(elapsed: TimeInterval) -> String {
        let doing = stage?.uppercased() ?? "THINKING"
        return elapsed >= clockDelay ? "\(doing)  \(Int(elapsed))s" : doing
    }
}
