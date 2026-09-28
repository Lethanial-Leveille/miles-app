import Foundation
import Combine

// Chat runs over REST. A turn streams from POST /chat/stream and falls back to the blocking
// POST /chat when that never starts. The server's /ws socket is not used: it runs the same
// turn with no streaming, and its handler has never worked (asyncio.run inside a live loop).
@MainActor
final class ChatService: ObservableObject {

    enum Connection {
        case checking, online, offline
    }

    @Published var messages:     [ChatMessage] = []
    @Published var connection:   Connection = .checking
    @Published var isTyping:     Bool = false
    // True for the whole turn. isTyping goes false once words arrive, but the reply is still
    // coming, and a second send in that window would start a turn on top of this one.
    @Published private(set) var isResponding = false
    // What Nova is doing while a tool runs, shown in place of THINKING
    @Published private(set) var stage: String? = nil
    @Published var errorMessage: String? = nil
    // When the current turn began, so the typing indicator can show how long it has been waiting
    @Published private(set) var turnStartedAt: Date? = nil
    // Bumped once per reply, a clean trigger for the haptic that history loading will never fire
    @Published private(set) var replyCount = 0

    // Nova reads the last 20 messages from every device on each turn, so show her that much
    private let recentContextCount = 20
    // .task restarts every time the Chat tab reappears; this keeps the context from being added twice
    private var hasLoadedRecent = false

    // Chat opens on the same conversation Nova is holding, including what was said in the room,
    // instead of a blank screen that hides context she can see
    func loadRecentConversation() async {
        guard !hasLoadedRecent else { return }
        hasLoadedRecent = true
        do {
            let rows = try await APIService.fetchHistory(limit: recentContextCount, offset: 0)
            // Anything sent while this was loading belongs after the older context
            messages = rows.map(ChatMessage.init(history:)) + messages
        } catch {
            // Chat works without context, and checkConnection is what reports an outage
            hasLoadedRecent = false
        }
    }

    func checkConnection() async {
        connection = .checking
        do {
            _ = try await APIService.fetchStatus()
            connection = .online
        } catch {
            connection = .offline
        }
    }

    // Returns the reply as the Pi saved it, empty when Nova chose not to answer, or nil when
    // the turn failed or its end never arrived. Talk Mode speaks what comes back.
    @discardableResult
    func send(text: String, channel: APIService.Channel = .text) async -> String? {
        // Add the user bubble immediately so the UI feels instant
        messages.append(ChatMessage(role: .user, text: text))
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

        // Everything streamed so far and the bubble showing it. The bubble is made on the
        // first delta, so a turn Nova answers with silence never leaves an empty one behind.
        var streamed = ""
        var bubble: UUID? = nil
        var sawEvent = false
        var reply: String? = nil

        do {
            for try await event in APIService.chatStream(text: text, channel: channel) {
                sawEvent = true
                connection = .online

                switch event {
                case .delta(let piece):
                    streamed += piece
                    // The words are arriving, so the waiting indicator has nothing left to say
                    isTyping = false
                    stage = nil
                    bubble = write(streamed, into: bubble)

                case .stage(let words):
                    // A tool can start after Nova has already written a sentence, so the
                    // indicator comes back below that bubble rather than replacing it
                    stage = words
                    isTyping = true

                case .reset:
                    // What Nova says alongside a tool call is not part of the answer the tool
                    // produces, and it is not what the Pi saves, so the reader drops it too
                    streamed = ""
                    if let id = bubble { messages.removeAll { $0.id == id } }
                    bubble = nil
                    isTyping = true

                case .done(let final):
                    // The canonical text, exactly as it went into history, including the lines
                    // the backend adds in code. An empty one is a real answer: not meant for her.
                    let trimmed = final.trimmingCharacters(in: .whitespacesAndNewlines)
                    _ = write(trimmed, into: bubble)
                    reply = trimmed
                    replyCount += 1

                case .failure(let reason):
                    errorMessage = reason.isEmpty ? "The turn failed on the Pi." : reason
                }
            }
        } catch {
            // A turn that reached the Pi finishes there whatever happens to this connection,
            // tools and saving included, so asking again would run it twice. Only a turn that
            // never started is safe to retry, which is also the old backend with no stream route.
            // An expired login has already sent the app back to the login screen, and the
            // blocking route would only be refused the same way
            if case APIError.unauthorized = error {
                errorMessage = error.localizedDescription
                return nil
            }
            guard sawEvent else {
                return await sendWithoutStreaming(text: text, channel: channel)
            }
            if error is URLError { connection = .offline }
            errorMessage = error.localizedDescription
            // Whatever arrived before the break stays on screen: she did write it
        }
        return reply
    }

    // The blocking route, one request and the whole reply at the end. The fallback for a
    // stream that never started.
    private func sendWithoutStreaming(text: String, channel: APIService.Channel) async -> String? {
        do {
            let reply = try await APIService.chat(text: text, channel: channel)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            connection = .online
            messages.append(ChatMessage(role: .nova, text: reply))
            replyCount += 1
            return reply
        } catch {
            if error is URLError { connection = .offline }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // Puts the reply so far in its own bubble, making it on first use. ChatMessage is a value
    // type, so growing text means replacing the whole element, and reusing the id keeps
    // SwiftUI redrawing that bubble instead of animating in a new one per token.
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
