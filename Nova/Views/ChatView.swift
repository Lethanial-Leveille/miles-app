import SwiftUI

struct ChatView: View {
    @StateObject private var service = ChatService()
    @StateObject private var speech  = SpeechService()
    @AppStorage("autoSendOnStop") private var autoSend = false

    @State private var inputText = ""

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Theme.accent.opacity(0.15))

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(service.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }

                            if service.isTyping {
                                NovaTypingIndicator(startedAt: service.turnStartedAt ?? Date())
                                    .id("typing")
                            }

                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.top, 12)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: service.messages.count) {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom") }
                    }
                    .onChange(of: service.isTyping) {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom") }
                    }
                }

                if let error = service.errorMessage {
                    Text(error)
                        .novaFont(12, design: .monospaced)
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }

                if speech.permissionDenied {
                    Text("Microphone or speech recognition permission denied. Enable in Settings.")
                        .novaFont(11, design: .monospaced)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }

                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Theme.accent.opacity(0.15))

                inputBar
            }
        }
        .task {
            await service.checkConnection()
            await service.loadRecentConversation()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: service.replyCount)
        // Keep inputText in sync with the live speech transcript
        .onChange(of: speech.transcript) { _, newValue in
            inputText = newValue
        }
        // If auto-send is on, send the moment recording stops
        .onChange(of: speech.isRecording) { _, nowRecording in
            if !nowRecording && autoSend && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sendMessage()
            }
        }
    }

    // MARK: Header

    private var isOnline: Bool { service.connection == .online }

    private var connectionLabel: String {
        switch service.connection {
        case .checking: return "CONNECTING..."
        case .online:   return "ONLINE"
        case .offline:  return "OFFLINE  TAP TO RETRY"
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .frame(width: 8, height: 8)
                .foregroundColor(isOnline ? Theme.accent : Theme.textSecondary)
                .shadow(color: isOnline ? Theme.accentGlow : .clear, radius: 4)

            Text("NOVA")
                .novaFont(14, weight: .bold, design: .monospaced)
                .foregroundColor(Theme.textPrimary)
                .tracking(4)

            Button {
                Task { await service.checkConnection() }
            } label: {
                Text(connectionLabel)
                    .novaFont(10, design: .monospaced)
                    .foregroundColor(isOnline ? Theme.accent : Theme.textSecondary)
                    .tracking(2)
            }
            .disabled(service.connection != .offline)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Input bar

    private var canSend: Bool {
        !service.isTyping && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            // Mic button — left of the text field
            Button {
                Task { await speech.toggleRecording() }
            } label: {
                Image(systemName: speech.isRecording ? "mic.fill" : "mic")
                    .novaFont(15, weight: .medium)
                    .foregroundColor(speech.isRecording ? Theme.accent : Theme.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .shadow(color: speech.isRecording ? Theme.accentGlow : .clear, radius: 10)
                    .animation(.easeInOut(duration: 0.25), value: speech.isRecording)
            }

            TextField("", text: $inputText, prompt: Text("Message Nova").foregroundColor(Theme.textSecondary), axis: .vertical)
                .lineLimit(1...5)
                .novaFont(15)
                .foregroundColor(Theme.textPrimary)
                .tint(Theme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(
                            speech.isRecording ? Theme.accent.opacity(0.6) : Theme.accent.opacity(0.3),
                            lineWidth: 1
                        )
                )
                .animation(.easeInOut(duration: 0.25), value: speech.isRecording)
                // onSubmit also fired when the field lost focus, so switching tabs sent a half
                // written message. In a vertical field the return key types a newline instead,
                // and exactly one newline typed at the end is the return key and nothing else:
                // a tab switch adds no character, and a paste adds more than one.
                .onChange(of: inputText) { oldValue, newValue in
                    guard newValue.count == oldValue.count + 1, newValue.hasSuffix("\n") else { return }
                    inputText = String(newValue.dropLast())
                    sendMessage()
                }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up")
                    .novaFont(14, weight: .bold)
                    .foregroundColor(Theme.background)
                    .frame(width: 38, height: 38)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .shadow(color: Theme.accentGlow, radius: 6)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Actions

    private func sendMessage() {
        // One turn at a time: a calendar change waits for the very next message to be
        // its yes or no, so overlapping sends could answer the wrong question
        guard canSend else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if speech.isRecording { speech.stopRecording() }
        inputText = ""
        Task { await service.send(text: text) }
    }
}

#Preview {
    ChatView()
}
