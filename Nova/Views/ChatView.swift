import SwiftUI

struct ChatView: View {
    @StateObject private var service = WebSocketService()
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
                                NovaTypingIndicator()
                                    .id("typing")
                            }

                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.top, 12)
                    }
                    .onChange(of: service.messages.count) {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom") }
                    }
                    .onChange(of: service.isTyping) {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom") }
                    }
                }

                if let error = service.errorMessage {
                    Text(error)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }

                if speech.permissionDenied {
                    Text("Microphone or speech recognition permission denied. Enable in Settings.")
                        .font(.system(size: 11, design: .monospaced))
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
        .task { await service.connect() }
        .onDisappear { service.disconnect() }
        // Keep inputText in sync with the live speech transcript
        .onChange(of: speech.transcript) { _, newValue in
            inputText = newValue
        }
        // If auto-send is on, send the moment recording stops
        .onChange(of: speech.isRecording) { _, nowRecording in
            if !nowRecording && autoSend && !inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                sendMessage()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .frame(width: 8, height: 8)
                .foregroundColor(service.isConnected ? Theme.accent : Theme.textSecondary)
                .shadow(color: service.isConnected ? Theme.accentGlow : .clear, radius: 4)

            Text("NOVA")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
                .tracking(4)

            Text(service.isConnected ? "ONLINE" : "CONNECTING...")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(service.isConnected ? Theme.accent : Theme.textSecondary)
                .tracking(2)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Input bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            // Mic button — left of the text field
            Button {
                Task { await speech.toggleRecording() }
            } label: {
                Image(systemName: speech.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(speech.isRecording ? Theme.accent : Theme.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .shadow(color: speech.isRecording ? Theme.accentGlow : .clear, radius: 10)
                    .animation(.easeInOut(duration: 0.25), value: speech.isRecording)
            }

            TextField("", text: $inputText)
                .font(.system(size: 15))
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
                .disabled(!service.isConnected)
                .onSubmit { sendMessage() }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.background)
                    .frame(width: 38, height: 38)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .shadow(color: Theme.accentGlow, radius: 6)
            }
            .disabled(!service.isConnected || inputText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if speech.isRecording { speech.stopRecording() }
        inputText = ""
        Task { await service.send(text: text) }
    }
}

#Preview {
    ChatView()
}
