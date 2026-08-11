import Foundation

// One row from GET /memories. Names and nullability mirror the memories
// table on the Pi: category is the only column without NOT NULL, so it is
// the only optional here. There is deliberately no createdAt: the column
// exists in the table but the endpoint does not select it, so it can never
// arrive in the response.
struct Memory: Decodable, Identifiable {
    let id: Int
    let content: String
    let category: String?
    let source: String
    let confidence: String
    let status: String
}

// GET /memories returns a paginated envelope, not a bare array.
// total counts every active memory on the server, not the number in this
// page, so it drives both the header count and the decision about whether
// another page is worth requesting.
struct MemoriesResponse: Decodable {
    let total: Int
    let memories: [Memory]
}
