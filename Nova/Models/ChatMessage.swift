import Foundation

struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    let text: String
    let timestamp: Date

    enum Role {
        case user
        case nova
    }

    init(role: Role, text: String) {
        self.id        = UUID()
        self.role      = role
        self.text      = text
        self.timestamp = Date()
    }
}
