import Foundation

struct Message: Decodable, Identifiable {
    let id: String
    let role: String       // "user" or "assistant"
    let content: String
    let timestamp: Date?
}
