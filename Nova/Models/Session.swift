import Foundation

// A session is a conversation the Pi starts with a purpose, like the nightly review, separate
// from the main chat. The shapes here follow docs/SESSIONS_CONTRACT.md exactly. Keys arrive in
// snake_case and the shared decoder converts them, as it does for every other model.
struct Session: Codable, Identifiable, Equatable {
    let id: Int
    let type: String
    let title: String?
    // From the Pi's registry of session types, so it is always there
    let purpose: String
    // "open", "closed" or "missed". A var so a close seen mid stream can update it in place.
    var status: String
    // A plain day ("2026-11-24") for once a day types, nil for every other type
    let forDay: String?
    let createdAt: String
    let openedAt: String?
    let lastMessageAt: String?
    var closedAt: String?
    var summary: String?

    var isOpen: Bool { status == "open" }

    // "nightly_review" reads as "NIGHTLY REVIEW", so a new type needs no app update to show
    var typeLabel: String {
        type.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    var created: Date? { SessionTime.parse(createdAt) }
    var lastActivity: Date? { SessionTime.parse(lastMessageAt) ?? created }
    var closed: Date? { SessionTime.parse(closedAt) }
}

// One message as the app renders it: only the text of what was stored
struct SessionMessage: Codable, Identifiable, Equatable {
    let id: Int
    // "user" or "assistant"
    let role: String
    let text: String
    let createdAt: String

    var created: Date? { SessionTime.parse(createdAt) }
}

// GET /sessions
struct SessionList: Codable {
    let sessions: [Session]
}

// GET /sessions/{id}, and POST /sessions, which answers with the same body
struct SessionDetail: Codable {
    let session: Session
    let messages: [SessionMessage]
}

// POST /sessions/{id}/close
struct SessionEnvelope: Codable {
    let session: Session
}

// Session times are the Pi's wall clock in New York, written with no offset. Reading them in
// the phone's own zone would shift every one by hours on a trip, so this reader always uses
// America/New_York. ServerDate keeps reading the device zone for the screens that already use it.
enum SessionTime {
    static let zone = TimeZone(identifier: "America/New_York")!

    private static let wholeSeconds: DateFormatter = {
        let formatter = DateFormatter()
        // POSIX locale so a 12 hour clock or another calendar in Settings cannot change how it parses
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    // Accepts "2026-11-24T21:30:04" and "2026-11-24T21:30:04.118201". The fraction is read by
    // hand so any number of digits works and none of the precision is dropped.
    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let parts = string.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let whole = wholeSeconds.date(from: String(parts[0])) else { return nil }
        guard parts.count == 2 else { return whole }
        let digits = parts[1]
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let fraction = Double("0.\(digits)") else { return nil }
        return whole.addingTimeInterval(fraction)
    }

    // for_day is a date on the calendar, not an instant, so it is read and written in one fixed
    // zone and never moves to the day before or after
    private static let plainDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dayLabel: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE MMM d"
        return formatter
    }()

    // "2026-11-24" shows as "TUE NOV 24", and anything unexpected shows as it came
    static func dayText(_ forDay: String) -> String {
        guard let day = plainDay.date(from: forDay) else { return forDay }
        return dayLabel.string(from: day).uppercased()
    }

    // An instant shown on this phone's clock, which is the right way to show a moment once it
    // has been read correctly
    private static let momentLabel: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d  HH:mm"
        return formatter
    }()

    static func momentText(_ date: Date) -> String {
        momentLabel.string(from: date).uppercased()
    }
}

extension ChatMessage {
    // A stored session message on the same thread the main chat draws, at the time it was said
    init(session message: SessionMessage) {
        self.id        = UUID()
        self.role      = message.role == "user" ? .user : .nova
        self.text      = message.text
        self.timestamp = message.created ?? Date()
        self.fromRoom  = false
    }
}
