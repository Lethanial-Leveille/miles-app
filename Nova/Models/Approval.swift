import Foundation

// A request the Mac is waiting on: a text to a student's chat, or an Evallo edit. Nothing
// happens until it is approved here, one at a time, within two hours of being proposed.
struct Approval: Decodable, Identifiable {
    let id: Int
    let kind: String
    let summary: String
    // The exact words that will be sent, for a text. Nil for an Evallo edit.
    let text: String?
    let chatName: String?
    let status: String
    let expiresAt: String

    var isText: Bool { kind == "imessage" }

    // The Pi writes UTC with an offset ("2026-11-23T21:00:00+00:00").
    var expiresDate: Date? { ISO8601DateFormatter().date(from: expiresAt) }
}

struct ApprovalList: Decodable {
    let approvals: [Approval]
}
