import SwiftUI

// One session as a conversation, drawn with the main chat's own thread, markdown and typing ring.
// While it is open he can reply or close it; once it is closed or missed it is read only, with
// the summary on top of the thread.
struct SessionView: View {
    @StateObject private var service: SessionService
    @State private var inputText = ""
    @State private var confirmingClose = false
    @FocusState private var typing: Bool

    init(sessionID: Int) {
        _service = StateObject(wrappedValue: SessionService(sessionID: sessionID))
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScreenHeader(title: service.session?.typeLabel ?? "SESSION") {
                    if service.isOpen {
                        Button {
                            confirmingClose = true
                        } label: {
                            if service.isClosing {
                                ProgressView().tint(Theme.accent)
                            } else {
                                Text("CLOSE")
                                    .novaFont(10, weight: .bold, design: .monospaced)
                                    .foregroundColor(Theme.accent)
                            }
                        }
                        .disabled(service.isClosing || service.isResponding)
                    }
                }

                if let session = service.session {
                    purposeBar(session)
                }

                thread

                if let error = service.errorMessage {
                    Text(error)
                        .novaFont(12, design: .monospaced)
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }

                divider

                if service.isOpen {
                    inputBar
                } else if !service.isLoading {
                    Text(readOnlyLabel)
                        .novaFont(10, weight: .medium, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                        .tracking(2)
                        .padding(.vertical, 14)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await service.load() }
        .sensoryFeedback(.impact(weight: .light), trigger: service.replyCount)
        .confirmationDialog("Close this session?", isPresented: $confirmingClose, titleVisibility: .visible) {
            Button("Close and summarize") {
                Task { await service.close() }
            }
            Button("Keep it open", role: .cancel) {}
        } message: {
            Text("Nova writes a summary and the session becomes read only.")
        }
    }

    private var readOnlyLabel: String {
        switch service.session?.status {
        case "missed": return "MISSED  READ ONLY"
        default:       return "CLOSED  READ ONLY"
        }
    }

    private var divider: some View {
        Rectangle()
            .frame(height: 1)
            .foregroundColor(Theme.textSecondary.opacity(0.18))
    }

    private func purposeBar(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title = session.title {
                Text(title)
                    .novaFont(14, weight: .medium)
                    .foregroundColor(Theme.textPrimary)
            }
            Text(session.purpose)
                .novaFont(13)
                .foregroundColor(Theme.textSecondary)
            if let day = session.forDay {
                Text(SessionTime.dayText(day))
                    .novaFont(10, design: .monospaced)
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let session = service.session, !session.isOpen || service.refusedAsClosed {
                        summaryCard(session)
                    }

                    ForEach(service.messages) { message in
                        ThreadMessage(message: message)
                            .id(message.id)
                    }

                    if service.isTyping {
                        NovaTypingIndicator(startedAt: service.turnStartedAt ?? Date(), stage: service.stage)
                            .id("typing")
                    }

                    if service.isLoading {
                        ProgressView().tint(Theme.accent).padding(.top, 40)
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.top, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { typing = false }
            .onChange(of: service.messages.count) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom") }
            }
            .onChange(of: service.isTyping) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom") }
            }
            .onChange(of: service.messages.last?.text) {
                proxy.scrollTo("bottom")
            }
        }
    }

    // What the close wrote, kept at the top where a read only session starts
    private func summaryCard(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.status == "missed" ? "MISSED" : "SUMMARY")
                    .novaFont(9, weight: .bold, design: .monospaced)
                    .foregroundColor(Theme.textSecondary)
                    .tracking(2)
                Spacer()
                if let closed = session.closed {
                    Text(SessionTime.momentText(closed))
                        .novaFont(9, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            if let summary = session.summary, !summary.isEmpty {
                MarkdownText(source: summary)
                    .novaFont(14)
                    .foregroundColor(Theme.textPrimary)
                    .tint(Theme.accent)
            } else {
                Text(session.status == "missed" ? "Nothing was said in this one." : "No summary was written.")
                    .novaFont(13)
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: Input

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        service.isOpen && !service.isResponding && !service.isClosing
            && !trimmedInput.isEmpty && trimmedInput.unicodeScalars.count <= SessionService.maxLength
    }

    private var inputBar: some View {
        VStack(spacing: 4) {
            if trimmedInput.unicodeScalars.count > SessionService.maxLength {
                Text("\(trimmedInput.unicodeScalars.count) OF \(SessionService.maxLength) CHARACTERS")
                    .novaFont(10, design: .monospaced)
                    .foregroundColor(Theme.alert)
            }
            HStack(spacing: 8) {
                TextField("", text: $inputText, prompt: Text("Reply").foregroundColor(Theme.textSecondary), axis: .vertical)
                    .lineLimit(1...5)
                    .focused($typing)
                    .novaFont(15)
                    .foregroundColor(Theme.textPrimary)
                    .tint(Theme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 19))
                    .overlay(
                        RoundedRectangle(cornerRadius: 19)
                            .stroke(Theme.textSecondary.opacity(0.25), lineWidth: 1)
                    )
                    // Same return key rule as the main chat: one newline typed at the end sends
                    .onChange(of: inputText) { oldValue, newValue in
                        guard newValue.count == oldValue.count + 1, newValue.hasSuffix("\n") else { return }
                        inputText = String(newValue.dropLast())
                        sendMessage()
                    }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up")
                        .novaFont(14, weight: .bold)
                        .foregroundColor(Theme.onAccent)
                        .frame(width: 38, height: 38)
                        .background(Theme.accent)
                        .clipShape(Circle())
                        .shadow(color: canSend ? Theme.accentGlow : .clear, radius: 6)
                        .opacity(canSend ? 1 : 0.35)
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func sendMessage() {
        guard canSend else { return }
        let text = trimmedInput
        inputText = ""
        Task { await service.send(text: text) }
    }
}
