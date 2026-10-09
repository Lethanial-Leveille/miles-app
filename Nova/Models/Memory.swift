import Foundation

struct Memory: Decodable, Identifiable {
    let id: Int
    let content: String
    let category: String?
    let source: String?
    let confidence: String?
    // Only the active listing sends this; pending rows leave it out
    let status: String?
    // Pending rows only: the stored memory this one is close to, or nil when nothing is
    let similarTo: MemoryRef?

    private enum CodingKeys: String, CodingKey {
        case id, content, category, source, confidence, status, similarTo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id       = try container.decode(Int.self, forKey: .id)
        content  = try container.decode(String.self, forKey: .content)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        source   = try container.decodeIfPresent(String.self, forKey: .source)
        status   = try container.decodeIfPresent(String.self, forKey: .status)
        // Only a hint, so a hint the app cannot read must not fail the whole pending list
        similarTo = try? container.decodeIfPresent(MemoryRef.self, forKey: .similarTo)

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

// Just enough of a memory to show it beside another. The server also sends a similarity
// score, left undecoded on purpose: it cannot tell a duplicate from two different facts
// about the same person, so it is never shown as if it could.
struct MemoryRef: Decodable, Identifiable {
    let id: Int
    let content: String
}

// Two stored memories that read alike, from GET /memories/similar. a is always the older.
struct MemoryPair: Decodable, Identifiable {
    let a: MemoryRef
    let b: MemoryRef

    var id: String { "\(a.id)-\(b.id)" }
}

struct MemoryPairs: Decodable {
    let pairs: [MemoryPair]
}

// POST /memories/merge/draft. Stores nothing. drafted is false when the model could not be
// reached, and content is then just the longer of the two.
struct MergeDraft: Decodable {
    let content: String
    let drafted: Bool
}

// POST /memories/merge. The kept memory is superseded, so id is new; the other is deleted.
struct MergeResult: Decodable {
    let id: Int
    let replaced: Int
    let deleted: Int
}
