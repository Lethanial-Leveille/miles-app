import Foundation
import Combine

// One session on screen: its messages from the Pi, a turn streamed in as it is written, and the
// switch to read only once it closes. The streaming follows ChatService turn for turn, so a
// session reply looks and behaves exactly like a chat reply.
@MainActor
final class SessionService: ObservableObject {

    let sessionID: Int

    @Published private(set) var session: Session?
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isTyping = false
    @Published private(set) var isResponding = false
    @Published private(set) var isClosing = false
    @Published private(set) var stage: String? = nil
    @Published private(set) var turnStartedAt: Date? = nil
    @Published private(set) var replyCount = 0
    @Published var errorMessage: String? = nil
    // Set when the Pi said 409: whatever the last load showed, the session is not open now
    @Published private(set) var refusedAsClosed = false

    // The Pi takes 1 to 4000 characters a turn
    static let maxLength = 4000

    init(sessionID: Int) {
        self.sessionID = sessionID
    }

    var isOpen: Bool { (session?.isOpen ?? false) && !refusedAsClosed }

    func load() async {
        do {
            let detail = try await APIService.fetchSession(id: sessionID)
            apply(detail)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // Takes the Pi's copy as the truth, unless a turn is mid stream and still drawing its bubble
    private func apply(_ detail: SessionDetail) {
        session = detail.session
        if !isResponding {
            messages = detail.messages.map(ChatMessage.init(session:))
        }
    }

    func send(text: String) async {
        guard isOpen, !isResponding else { return }
        let userBubble = ChatMessage(role: .user, text: text)
        messages.append(userBubble)
        turnStartedAt = Date()
        isTyping = true
        isResponding = true
        stage = nil
        errorMessage = nil
        defer {
            isTyping = false
            isResponding = false
            stage = nil
        }

        var streamed = ""
        var bubble: UUID? = nil
        var closedSummary: String? = nil

        do {
            for try await event in APIService.sessionTurn(id: sessionID, text: text) {
                switch event {
                case .delta(let piece):
                    streamed += piece
                    isTyping = false
                    stage = nil
                    bubble = write(streamed, into: bubble)

                case .stage(let words):
                    stage = words
                    isTyping = true

                case .reset:
                    streamed = ""
                    if let id = bubble { messages.removeAll { $0.id == id } }
                    bubble = nil
                    isTyping = true

                case .closed(let summary):
                    // Always before done, so the reply still finishes in its bubble below
                    closedSummary = summary
                    markClosed(summary: summary)

                case .done(let final):
                    let trimmed = final.trimmingCharacters(in: .whitespacesAndNewlines)
                    _ = write(trimmed, into: bubble)
                    replyCount += 1

                case .failure(let reason):
                    errorMessage = reason.isEmpty ? "The turn failed on the Pi." : reason
                }
            }
        } catch APIError.notOpen(let reason) {
            // Refused before anything ran, so the message was never stored and its bubble goes
            messages.removeAll { $0.id == userBubble.id }
            refusedAsClosed = true
            errorMessage = reason
            await refreshQuietly()
            return
        } catch {
            // As in the main chat, a turn that reached the Pi finishes there, so it is not resent
            errorMessage = error.localizedDescription
        }

        if closedSummary != nil {
            // Picks up closed_at and anything else the Pi wrote while closing
            await refreshQuietly()
        }
    }

    // Returns the summary, or nil when the close failed. A 409 means it was already closed or
    // missed, which leaves the screen read only either way.
    @discardableResult
    func close() async -> String? {
        guard !isClosing else { return nil }
        isClosing = true
        errorMessage = nil
        defer { isClosing = false }
        do {
            let closed = try await APIService.closeSession(id: sessionID)
            session = closed
            SessionRouter.shared.refresh()
            return closed.summary ?? ""
        } catch APIError.notOpen(let reason) {
            refusedAsClosed = true
            errorMessage = reason
            await refreshQuietly()
        } catch {
            errorMessage = error.localizedDescription
        }
        return nil
    }

    private func markClosed(summary: String) {
        session?.status = "closed"
        session?.summary = summary
        SessionRouter.shared.refresh()
    }

    // Only the session itself: the messages on screen are already right, and a reply that just
    // streamed in should not be redrawn from the stored copy under his eyes
    private func refreshQuietly() async {
        if let detail = try? await APIService.fetchSession(id: sessionID) {
            session = detail.session
        }
    }

    // Same in place rewrite ChatService uses, so the streaming bubble keeps its identity
    private func write(_ text: String, into existing: UUID?) -> UUID {
        if let id = existing, let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index] = ChatMessage(id: id, role: .nova, text: text)
            return id
        }
        let message = ChatMessage(role: .nova, text: text)
        messages.append(message)
        return message.id
    }
}
