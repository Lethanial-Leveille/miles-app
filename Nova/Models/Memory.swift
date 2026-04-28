import Foundation

struct Memory: Decodable, Identifiable {
    let id: Int
    let content: String
    let createdAt: String?
}
