import Foundation

// A task as the Pi describes it (docs/TASKS_CONTRACT.md). Dates are plain "yyyy-MM-dd"
// strings and stay strings: they are shown, never converted to a time zone.
struct NovaTask: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let shortTitle: String?
    let notes: String?
    let daily: Bool
    // "pending" or "done"
    let status: String
    let mustDo: Bool
    let scheduledFor: String?
    let dueDate: String?
    let overdue: Bool
    let hasBlock: Bool
    let source: String?

    var isDone: Bool { status == "done" }
    // What the row shows: the short title when there is one
    var displayTitle: String {
        if let short = shortTitle, !short.isEmpty { return short }
        return title
    }
}

// One day of GET /tasks/overview. label is "Today" or e.g. "Thursday Nov 26".
struct TaskDayGroup: Decodable, Identifiable, Hashable {
    let date: String
    let label: String
    let tasks: [NovaTask]

    var id: String { date }
}

// GET /tasks/overview. today is the Pi's 4am day.
struct TasksOverview: Decodable {
    let today: String
    let days: [TaskDayGroup]
    let backlog: [NovaTask]
}

// complete, reopen and backlog all answer with the task as it now stands
struct TaskResponse: Decodable {
    let task: NovaTask
}

enum TaskDate {
    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let shower: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE MMM d"
        return formatter
    }()

    // "2026-11-30" becomes "Mon Nov 30" in any device time zone. Anything unparseable is
    // returned as it came.
    static func display(_ day: String) -> String {
        guard let date = parser.date(from: day) else { return day }
        return shower.string(from: date)
    }

    // The yyyy-MM-dd for the calendar day a date picker shows. The picker works in the
    // device's time zone, so the day is read in it, with no zone conversion afterwards.
    static func string(fromPicker date: Date, calendar: Calendar? = nil) -> String {
        // Always Gregorian: a Buddhist or Japanese device calendar would send year 2569 or 8
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        let parts = (calendar ?? gregorian).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }
}
