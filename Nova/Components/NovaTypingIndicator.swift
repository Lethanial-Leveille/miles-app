import SwiftUI

// TimelineView drives both the dots and the clock, so there is no Timer to clean up.
// The previous Timer was never invalidated and kept firing after the indicator disappeared.
struct NovaTypingIndicator: View {
    let startedAt: Date
    // "Checking your calendar" while a tool runs, nil while Nova is only thinking
    var stage: String? = nil

    // A quick reply should never flash a clock; only a turn slow enough to feel stuck shows one
    private let clockDelay: TimeInterval = 3

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 0.4)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            let phase = Int(elapsed / 0.4) % 3

            HStack(alignment: .bottom, spacing: 0) {
                HStack(spacing: 10) {
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .frame(width: 7, height: 7)
                                .foregroundColor(Theme.accent)
                                .opacity(phase == index ? 1.0 : 0.3)
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: phase)

                    // A stage is news worth showing at once; plain thinking waits for the delay
                    if let stage {
                        Text(elapsed >= clockDelay ? "\(stage.uppercased()) \(Int(elapsed))s" : stage.uppercased())
                            .novaFont(10, design: .monospaced)
                            .monospacedDigit()
                            .foregroundColor(Theme.accent)
                            .tracking(1)
                    } else if elapsed >= clockDelay {
                        Text("THINKING \(Int(elapsed))s")
                            .novaFont(10, design: .monospaced)
                            .monospacedDigit()
                            .foregroundColor(Theme.textSecondary)
                            .tracking(1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Spacer(minLength: 48)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }
}
