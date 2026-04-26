import Foundation
import Combine

@MainActor
class WebSocketService: ObservableObject {

    @Published var messages:     [ChatMessage] = []
    @Published var isConnected:  Bool = false
    @Published var isTyping:     Bool = false
    @Published var errorMessage: String? = nil

    private var webSocketTask: URLSessionWebSocketTask?

    // MARK: Connection lifecycle

    func connect() async {
        guard !isConnected else { return }

        do {
            let token = try await AuthService.getValidAccessToken()
            guard let url = URL(string: Constants.API.webSocketURL) else { return }

            let session = URLSession(configuration: .default)
            webSocketTask = session.webSocketTask(with: url)
            webSocketTask?.resume()

            // Authenticate immediately after opening the socket
            try await sendRaw(["type": "auth", "token": token])

            // Wait for auth_ok before marking connected
            try await awaitAuthConfirmation()

            isConnected = true
            errorMessage = nil

            // Start the receive loop
            receiveLoop()

        } catch {
            errorMessage = error.localizedDescription
            isConnected = false
        }
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    // MARK: Sending messages

    func send(text: String) async {
        guard isConnected else { return }

        // Add the user bubble immediately so the UI feels instant
        messages.append(ChatMessage(role: .user, text: text))
        isTyping = true

        do {
            try await sendRaw(["type": "message", "text": text])
        } catch {
            isTyping = false
            errorMessage = "Failed to send message."
        }
    }

    // MARK: Private helpers

    private func sendRaw(_ dict: [String: String]) async throws {
        let data = try JSONSerialization.data(withJSONObject: dict)
        guard let string = String(data: data, encoding: .utf8) else { return }
        try await webSocketTask?.send(.string(string))
    }

    private func awaitAuthConfirmation() async throws {
        guard let task = webSocketTask else { return }

        let message = try await task.receive()

        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "auth_ok"
        else {
            throw AuthError.invalidCredentials
        }
    }

    // Runs in a loop, waiting for the next message from the server
    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                switch result {
                case .success(let message):
                    if case .string(let text) = message {
                        self.handleIncoming(text)
                    }
                    // Keep the loop going for the next message
                    self.receiveLoop()

                case .failure:
                    self.isConnected = false
                    self.isTyping = false
                }
            }
        }
    }

    private func handleIncoming(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type_ = json["type"] as? String
        else { return }

        switch type_ {
        case "response":
            if let raw = json["text"] as? String {
                // Strip bracketed emotion tags like [calmly] before displaying
                let cleaned = raw.replacingOccurrences(
                    of: "\\[.*?\\]\\s*",
                    with: "",
                    options: .regularExpression
                )
                isTyping = false
                messages.append(ChatMessage(role: .nova, text: cleaned))
            }

        case "error":
            isTyping = false
            errorMessage = json["message"] as? String ?? "Unknown error from server."

        default:
            break
        }
    }
}
