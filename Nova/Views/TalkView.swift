import SwiftUI

// Full screen conversation by voice. The whole screen is one button: tap to send what you said
// without waiting out the silence, or to cut Nova off while she speaks.
struct TalkView: View {
    @ObservedObject var chat: ChatService
    @StateObject private var session: TalkSession
    @Environment(\.dismiss) private var dismiss

    init(chat: ChatService) {
        self.chat = chat
        _session = StateObject(wrappedValue: TalkSession(chat: chat))
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Spacer()

                TalkWaveform(phase: session.phase, level: { session.level })
                    .padding(.bottom, 40)

                Text(statusLine)
                    .novaFont(13, weight: .bold, design: .monospaced)
                    .foregroundColor(Theme.accent)
                    .tracking(4)
                    .animation(nil, value: statusLine)

                Text(caption)
                    .novaFont(17)
                    .foregroundColor(session.phase == .speaking ? Theme.textPrimary : Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .padding(.horizontal, 32)
                    .padding(.top, 16)
                    .frame(minHeight: 110, alignment: .top)

                Spacer()

                if let notice = session.notice {
                    Text(notice)
                        .novaFont(12, design: .monospaced)
                        .foregroundColor(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                }

                Text(hint)
                    .novaFont(10, design: .monospaced)
                    .foregroundColor(Theme.textSecondary)
                    .tracking(3)
                    .padding(.bottom, 24)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { session.tap() }
        .sensoryFeedback(.impact(weight: .light), trigger: session.phase)
        .onAppear {
            // Nobody touches the screen in a spoken conversation, so it must not lock mid answer
            UIApplication.shared.isIdleTimerDisabled = true
            session.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            session.end()
        }
    }

    private var header: some View {
        HStack {
            Text("TALK MODE")
                .novaFont(14, weight: .bold, design: .monospaced)
                .foregroundColor(Theme.textPrimary)
                .tracking(4)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .novaFont(15, weight: .medium)
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .accessibilityLabel("End Talk Mode")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var statusLine: String {
        switch session.phase {
        case .starting:  return "WAKING UP"
        case .listening: return "LISTENING"
        case .thinking:  return chat.stage?.uppercased() ?? "THINKING"
        case .speaking:  return "NOVA"
        case .stopped:   return "ENDED"
        }
    }

    private var caption: String {
        switch session.phase {
        case .listening: return session.heard.isEmpty ? "Go ahead, Lethanial." : session.heard
        case .thinking:  return session.heard
        case .speaking:  return session.said
        default:         return ""
        }
    }

    private var hint: String {
        switch session.phase {
        case .listening: return "TAP TO SEND"
        case .speaking:  return "TAP TO CUT IN"
        default:         return " "
        }
    }
}
