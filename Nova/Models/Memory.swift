import Foundation

struct Memory: Decodable, Identifiable {
    let id: Int
    let content: String
    let category: String?
    let source: String?
    let confidence: String?
    // Only the active listing sends this; pending rows leave it out
    let status: String?

    private enum CodingKeys: String, CodingKey {
        case id, content, category, source, confidence, status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id       = try container.decode(Int.self, forKey: .id)
        content  = try container.decode(String.self, forKey: .content)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        source   = try container.decodeIfPresent(String.self, forKey: .source)
        status   = try container.decodeIfPresent(String.self, forKey: .status)

        // The server writes words like "high" today, but the column is untyped, so an
        // older numeric row must not fail the decode of an entire page
        if let word = try? container.decodeIfPresent(String.self, forKey: .confidence) {
            confidence = word
        } else if let number = try? container.decodeIfPresent(Double.self, forKey: .confidence) {
            confidence = String(number)
        } else {
            confidence = nil
        }
    }
}

// GET /memories wraps each page in an object so the full active count comes along with it
struct MemoryPage: Decodable {
    let total: Int
    let memories: [Memory]
}

// PATCH /memories/{id}. An edit makes a new row, so id is the one to show from now on.
// changed is false when the text matched what was already stored.
struct MemoryEdit: Decodable {
    let id: Int
    let replaced: Int?
    let changed: Bool
}

// One wording in a memory's chain, from GET /memories/{id}/history
struct MemoryVersion: Decodable, Identifiable {
    let id: Int
    let content: String
    let status: String
    let createdAt: String?
    let supersededBy: Int?
    let supersededAt: String?

    var createdDate: Date? { ServerDate.parse(createdAt) }
    var supersededDate: Date? { ServerDate.parse(supersededAt) }
}
