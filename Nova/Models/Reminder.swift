import Foundation

// A row from GET /reminders. Timers live in the same table, told apart by kind.
struct Reminder: Decodable, Identifiable {
    let id: Int
    let content: String
    // Naive local time from the Pi. Null for a reminder saved without a time, which is a note.
    let dueAt: String?
    let createdAt: String?
    let kind: String

    var isTimer: Bool { kind == "timer" }
    var dueDate: Date? { ServerDate.parse(dueAt) }
}
