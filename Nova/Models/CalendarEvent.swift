import Foundation

// GET /calendar/events. unreadable names calendars Google refused, so a short week can say why.
struct CalendarWeek: Decodable {
    let events: [CalendarEvent]
    let unreadable: [String]
}

struct CalendarEvent: Decodable, Identifiable {
    let id: String
    let calendar: String
    let title: String
    // "2026-09-16" for an all day event, or a full timestamp with its offset for a timed one
    let start: String
    let end: String
    let allDay: Bool
    let mine: Bool
    // Only MILES calendar events; the Pi refuses edits anywhere else
    let editable: Bool
    let repeating: Bool

    var startDate: Date? { Self.parse(start, allDay: allDay) }
    var endDate: Date? { Self.parse(end, allDay: allDay) }

    // The day this event is listed under, local midnight
    var day: Date? { startDate.map { Calendar.current.startOfDay(for: $0) } }

    private static let timed = ISO8601DateFormatter()
    private static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func parse(_ raw: String, allDay: Bool) -> Date? {
        // An all day event is a date, not a moment, so it belongs to this phone's day
        allDay ? dateOnly.date(from: raw) : timed.date(from: raw)
    }
}
