import Foundation

struct Memory: Decodable, Identifiable {
    let id: String
    let content: String
    // Stored as a raw string to avoid ISO8601 format mismatches, same pattern as Message
    let createdAt: String?
}
