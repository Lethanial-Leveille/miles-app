import Foundation

struct Memory: Decodable, Identifiable {
    let id: String
    let content: String
    let createdAt: Date?
}
