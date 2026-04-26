import SwiftUI

struct ChatView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var service = WebSocketService()

    @State private var inputText = ""

    var body: some View {
        ZStack {
            Theme.background(colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: Header
                header

                Divider()
                    .background(Theme.accent(colorScheme).opacity(0.2))

                // MARK: Messages
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

                            // Invisible anchor at the bottom to scroll to
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(.top, 12)
                    }
                    .onChange(of: service.messages.count) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom")
                        }
                    }
                    .onChange(of: service.isTyping) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom")
                        }
                    }
                }

                // MARK: Error banner
                if let error = service.errorMessage {
                    Text(error)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }

                Divider()
                    .background(Theme.accent(colorScheme).opacity(0.2))

                // MARK: Input bar
                inputBar
            }
        }
        .task {
            await service.connect()
        }
        .onDisappear {
            service.disconnect()
        }
    }

    // MARK: Header
    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .frame(width: 8, height: 8)
                .foregroundColor(service.isConnected ? Theme.accent(colorScheme) : .gray)
                .shadow(color: service.isConnected ? Theme.glow(colorScheme) : .clear, radius: 4)

            Text("NOVA")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.textPrimary(colorScheme))
                .tracking(4)

            Text(service.isConnected ? "ONLINE" : "CONNECTING...")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(service.isConnected ? Theme.accent(colorScheme) : Theme.textSecondary(colorScheme))
                .tracking(2)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Input bar
    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("", text: $inputText)
                .font(.system(size: 15))
                .foregroundColor(Theme.textPrimary(colorScheme))
                .tint(Theme.accent(colorScheme))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surface(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Theme.accent(colorScheme).opacity(0.3), lineWidth: 1)
                )
                .disabled(!service.isConnected)
                .onSubmit { sendMessage() }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.background(colorScheme))
                    .frame(width: 38, height: 38)
                    .background(Theme.accent(colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .shadow(color: Theme.glow(colorScheme), radius: 6)
            }
            .disabled(!service.isConnected || inputText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""

        Task {
            await service.send(text: text)
        }
    }
}

#Preview {
    ChatView()
}
