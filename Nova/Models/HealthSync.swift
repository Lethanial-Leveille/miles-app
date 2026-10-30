import Foundation

// What the app sends to POST /health/sync. A nil field is left out of the JSON, which the Pi reads
// as "no reading that day", and each day sent replaces the Pi's copy of that day.
struct HealthSyncPayload: Encodable {
    struct Day: Encodable {
        let day: String            // yyyy-MM-dd on this phone's calendar
        let steps: Int?
        let activeKcal: Double?
        let weightLb: Double?
    }

    struct Workout: Encodable {
        let id: String             // HealthKit's own id, so the same run sent twice is one row
        let kind: String
        let startedAt: Date
        let minutes: Double
        let distanceMi: Double?
        let kcal: Double?
    }

    let days: [Day]
    let workouts: [Workout]
}
