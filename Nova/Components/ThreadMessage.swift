import SwiftUI

// One message on the conversation thread. A thin line runs down the left of the chat, with a
// glowing ring wherever Nova speaks and a small grey dot wherever you do. Replaced the bubbles
// in the November 2026 redesign.
//
// Each message draws only its own piece of the line, in its background. A background is sized to
// exactly the view it is attached to, padding included, and ChatView stacks messages with no gap,
// so the pieces meet as one unbroken line.
struct ThreadMessage: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    // The strip the line runs down. Text starts just past it, so a long reply gives up very
    // little width to the thread
    private static let gutter: CGFloat = 14

    var body: some View {
        row
            .padding(.leading, Self.gutter + 10)
            .padding(.trailing, 16)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topLeading) { thread }
            .padding(.leading, 16)
    }

    // MARK: The thread

    private var thread: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Theme.accent.opacity(0.3))
                .frame(width: 1)

            node
                // Level with the first line of text: Nova's label, or your message itself
                .padding(.top, isUser ? 16 : 8)
        }
        .frame(width: Self.gutter)
    }

    @ViewBuilder
    private var node: some View {
        if isUser {
            Circle()
                .fill(Theme.textSecondary.opacity(0.7))
                .frame(width: 7, height: 7)
        } else {
            RingNode(color: nodeColor)
        }
    }

    // Blue for every reply for now. Green for "something was saved" needs the Pi to say when a
    // tool finished, which it does not yet
    private var nodeColor: Color {
        message.text.isEmpty ? Theme.textSecondary : Theme.listening
    }

    // MARK: The message

    @ViewBuilder
    private var row: some View {
        if !isUser && message.text.isEmpty {
            // Nova chose not to answer, which is worth saying instead of leaving a gap
            Text("NOVA STAYED QUIET")
                .novaFont(9, weight: .medium, design: .monospaced)
                .foregroundColor(Theme.textSecondary)
                .tracking(2)
                .padding(.top, 2)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if !isUser {
                    Text("NOVA")
                        .novaFont(9, weight: .bold, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                        .tracking(2)
                }

                content
                    .novaFont(15)
                    // Yours is a shade quieter, so her answers are what the eye lands on
                    .foregroundColor(isUser ? Theme.textPrimary.opacity(0.78) : Theme.textPrimary)
                    .tint(Theme.accent)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.text
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }

                HStack(spacing: 6) {
                    Text(formattedTime)
                        .novaFont(10, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)

                    if message.fromRoom {
                        Image(systemName: "hifispeaker.fill")
                            .novaFont(8)
                            .foregroundColor(Theme.textSecondary)
                            .accessibilityLabel("Said in the room")
                    }
                }
            }
        }
    }

    // Nova writes markdown on the text channel. What the user typed is shown literally,
    // so an asterisk in a question never turns into italics.
    @ViewBuilder
    private var content: some View {
        if isUser {
            Text(message.text)
        } else {
            MarkdownText(source: message.text)
        }
    }

    // Built once; a DateFormatter is expensive to create and this runs for every message on every render
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayAndTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d  HH:mm"
        return formatter
    }()

    // Context loaded from history can be days old, and a bare time would pass it off as today
    private var formattedTime: String {
        let formatter = Calendar.current.isDateInToday(message.timestamp) ? Self.timeFormatter : Self.dayAndTimeFormatter
        return formatter.string(from: message.timestamp)
    }
}

// Nova's mark on the thread: a ring with a lit centre, in the colour of what she did. Talk Mode
// will use the same ring, larger.
struct RingNode: View {
    let color: Color

    var body: some View {
        ZStack {
            // Covers the thread behind it, so the line stops at the ring instead of running through
            Circle()
                .fill(Theme.background)
            Circle()
                .stroke(color, lineWidth: 1.5)
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
        }
        .frame(width: 13, height: 13)
        .shadow(color: color.opacity(0.55), radius: 5)
        .accessibilityHidden(true)
    }
}
