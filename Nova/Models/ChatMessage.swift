import Foundation

struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    let text: String
    let timestamp: Date
    // Said out loud in the room rather than typed here. It is one conversation across both.
    let fromRoom: Bool

    enum Role {
        case user
        case nova
    }

    init(role: Role, text: String) {
        self.id        = UUID()
        self.role      = role
        self.text      = text
        self.timestamp = Date()
        self.fromRoom  = false
    }

    // Same bubble, new text. A streamed reply rewrites its own element as it grows,
    // and keeping the id is what stops SwiftUI treating each update as a new message.
    init(id: UUID, role: Role, text: String) {
        self.id        = id
        self.role      = role
        self.text      = text
        self.timestamp = Date()
        self.fromRoom  = false
    }

    // Brings a stored history row into the chat, keeping when and where it was said
    init(history message: Message) {
        self.id        = message.id
        self.role      = message.isUser ? .user : .nova
        self.text      = message.content
        self.timestamp = message.date ?? Date()
        self.fromRoom  = message.isFromRoom
    }
}
