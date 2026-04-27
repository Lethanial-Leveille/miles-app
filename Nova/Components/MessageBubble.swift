import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser { Spacer(minLength: 48) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(isUser ? "YOU" : "NOVA")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(isUser ? Theme.accent : Theme.accent.opacity(0.55))
                    .tracking(2)
                    .padding(.horizontal, 4)

                Text(cleaned)
                    .font(.system(size: 15))
                    .foregroundColor(isUser ? Theme.accent : Theme.textPrimary)
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

                Text(formattedTime)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    // Strip bracketed stage directions like [calmly] or [short pause]
    private var cleaned: String {
        let stripped = message.text.replacingOccurrences(
            of: "\\[[^\\]]*\\]\\s*",
            with: "",
            options: .regularExpression
        )
        return stripped.trimmingCharacters(in: .whitespaces)
    }

    private var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: message.timestamp)
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
