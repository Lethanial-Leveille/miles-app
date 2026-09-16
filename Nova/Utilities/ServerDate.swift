import Foundation

// History timestamps come from Python's isoformat() on the Pi: local time with no offset
// ("2026-09-14T01:08:42.123456"), and no fraction at all when the microseconds are zero.
// ISO8601DateFormatter rejects both, so they are read as local time on this phone,
// which is right as long as the phone and the Pi share a timezone.
enum ServerDate {
    private static let withFraction    = formatter("yyyy-MM-dd'T'HH:mm:ss.SSSSSS")
    private static let withoutFraction = formatter("yyyy-MM-dd'T'HH:mm:ss")

    static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        return withFraction.date(from: string) ?? withoutFraction.date(from: string)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        // POSIX locale so a 12 hour clock or another calendar in Settings cannot change how it parses
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }
}
