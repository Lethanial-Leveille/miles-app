import SwiftUI

// The header every screen pushed from Settings uses: back chevron, spaced title, and an
// optional control on the right. Includes the hairline below it.
struct ScreenHeader<Trailing: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .novaFont(14, weight: .medium)
                        .foregroundColor(Theme.accent)
                }
                .padding(.trailing, 8)
                .accessibilityLabel("Back")

                Text(title)
                    .novaFont(13, weight: .bold, design: .monospaced)
                    .foregroundColor(Theme.textPrimary)
                    .tracking(4)
                Spacer()
                trailing()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Rectangle()
                .frame(height: 1)
                .foregroundColor(Theme.accent.opacity(0.15))
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

// The quiet spaced label above a group of rows
struct SectionLabel: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .novaFont(9, weight: .medium, design: .monospaced)
                .foregroundColor(Theme.textSecondary)
                .tracking(3)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 6)
    }
}
