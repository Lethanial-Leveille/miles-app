import SwiftUI

// Draws a reply block by block. It parses on every render, which is cheap at chat message
// sizes and means there is no cached copy that could fall out of step with the text.
struct MarkdownText: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownParser.blocks(from: source).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(inline(text))

        case .heading(let level, let text):
            Text(inline(text))
                .novaFont(level <= 2 ? 17 : 15, weight: .bold)
                .foregroundColor(Theme.textPrimary)
                .padding(.top, 2)

        case .listItem(let marker, let depth, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .monospacedDigit()
                    .foregroundColor(Theme.accent)
                Text(inline(text))
            }
            .padding(.leading, CGFloat(depth) * 16)

        case .quote(let text):
            Text(inline(text))
                .foregroundColor(Theme.textSecondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.accent.opacity(0.5))
                        .frame(width: 2)
                }

        case .code(let text), .table(let text):
            // Code and tables keep their line structure, so they scroll sideways instead of wrapping
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .novaFont(13, design: .monospaced)
                    .foregroundColor(Theme.textPrimary)
                    .padding(10)
            }
            .background(Theme.background)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Theme.accent.opacity(0.15), lineWidth: 1)
            )

        case .rule:
            Rectangle()
                .fill(Theme.accent.opacity(0.2))
                .frame(height: 1)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
