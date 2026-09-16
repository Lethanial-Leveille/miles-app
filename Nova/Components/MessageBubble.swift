import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        if !isUser && message.text.isEmpty {
            // Nova chose not to answer, which is worth saying instead of drawing an empty bubble
            Text("NOVA STAYED QUIET")
                .novaFont(9, weight: .medium, design: .monospaced)
                .foregroundColor(Theme.textSecondary)
                .tracking(2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else {
            bubble
        }
    }

    private var bubble: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser { Spacer(minLength: 48) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(isUser ? "YOU" : "NOVA")
                        .novaFont(9, weight: .bold, design: .monospaced)
                        .foregroundColor(isUser ? Theme.accent : Theme.accent.opacity(0.55))
                        .tracking(2)

                    if message.fromRoom {
                        Image(systemName: "hifispeaker.fill")
                            .novaFont(8)
                            .foregroundColor(Theme.textSecondary)
                            .accessibilityLabel("Said in the room")
                    }
                }
                .padding(.horizontal, 4)

                content
                    .novaFont(15)
                    .foregroundColor(isUser ? Theme.accent : Theme.textPrimary)
                    .tint(Theme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser ? Theme.background : Theme.surface)
                    .clipShape(BubbleShape(isUser: isUser))
                    .overlay(
                        BubbleShape(isUser: isUser)
                            .stroke(
                                isUser ? Theme.accent : Theme.accent.opacity(0.3),
                                lineWidth: 1.5
                            )
                    )
                    // Without this the long press preview is a plain rectangle around the bubble
                    .contentShape(.contextMenuPreview, BubbleShape(isUser: isUser))
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.text
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }

                Text(formattedTime)
                    .novaFont(10, design: .monospaced)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
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

    // Built once; a DateFormatter is expensive to create and this runs for every bubble on every render
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

private struct BubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 16
        let sharpR: CGFloat = 4

        let tl: CGFloat = isUser ? r      : sharpR
        let tr: CGFloat = isUser ? sharpR : r
        let bl: CGFloat = isUser ? r      : r
        let br: CGFloat = isUser ? r      : sharpR

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                    radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                    radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                    radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                    radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}
