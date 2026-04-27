import SwiftUI

struct NovaTypingIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .frame(width: 7, height: 7)
                        .foregroundColor(Theme.accent)
                        .opacity(phase == index ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.4).repeatForever().delay(Double(index) * 0.15),
                            value: phase
                        )
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
        .onAppear {
            animateDots()
        }
    }

    private func animateDots() {
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            phase = (phase + 1) % 3
        }
    }
}
