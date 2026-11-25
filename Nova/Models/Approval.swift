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
    // What the Mac said when it finished ("sent ...", or why it failed). Nil until then.
    let result: String?
    let payload: Payload?

    // Only the keys the app shows; the rest of the payload stays on the Pi and Mac.
    struct Payload: Decodable {
        // A reminder is several messages sent in order: the words, then the Zoom link alone.
        let parts: [String]?
    }

    var isText: Bool { kind == "imessage" }
    var isPending: Bool { status == "pending" }

    // The messages in sending order; an older request without parts is one message.
    var messages: [String] {
        if let parts = payload?.parts, !parts.isEmpty { return parts }
        return text.map { [$0] } ?? []
    }

    // The Pi writes UTC with an offset ("2026-11-23T21:00:00+00:00").
    var expiresDate: Date? { ISO8601DateFormatter().date(from: expiresAt) }
}

struct ApprovalList: Decodable {
    let approvals: [Approval]
}

// A tapped MILES push that reported a problem, shown in full on the error screen.
struct PushNote: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let approvalID: Int?
}

// The Pi's answer to a watchdog decision.
struct WatchdogAnswer: Decodable {
    let status: String
    let message: String
}
