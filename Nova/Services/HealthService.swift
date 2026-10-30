import Foundation
import HealthKit

// Reads the last two weeks from Apple Health and sends a copy to the Pi, so Nova can answer
// "what do I weigh" or "how far did I run" in the room.
//
// The Pi cannot reach HealthKit: the data lives on this phone, and only an app the user has
// allowed may read it. So the copy is as fresh as the last sync, and the Pi tells Nova how old it
// is. Syncing happens when the app opens (and from the Settings row), not in the background.
// Background delivery needs a login that outlives the app's one hour token, and the only way back
// in after an hour is Face ID, which cannot run while the phone is in a pocket.
//
// The app only reads. It never writes to Health.
enum HealthService {

    private static let store = HKHealthStore()
    private static let enabledKey = "healthSyncEnabled"
    private static let lastSyncKey = "healthLastSync"

    // Long enough to cover a missed week and show a weight trend, short enough that one query
    // per type stays quick
    private static let lookbackDays = 14

    // Opening the app twice in a minute should not read and upload twice
    private static let minimumGap: TimeInterval = 5 * 60

    private static var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.bodyMass),
            // A workout's distance is read from these, by what kind of workout it was
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.distanceSwimming),
            HKObjectType.workoutType(),
        ]
    }

    // yyyy-MM-dd on the phone's own calendar. A fixed locale and Gregorian calendar, because a
    // phone set to another calendar would otherwise send the Pi a different year.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: State

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    // What the Settings row says under its title
    static func statusLine() -> String {
        guard isAvailable else { return "Health is not available on this device" }
        guard isEnabled else { return "Let Nova read steps, weight and runs" }
        guard let last = UserDefaults.standard.object(forKey: lastSyncKey) as? Date else {
            return "Connected. Not synced yet"
        }
        let ago = last.formatted(.relative(presentation: .named))
        return "Synced \(ago). Tap to sync now"
    }

    // MARK: Syncing

    // Shows iOS's Health permission sheet the first time. iOS never says which types were allowed
    // (a denied one just reads as empty), so a nil day on the Pi can mean either.
    static func connect() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
        UserDefaults.standard.set(true, forKey: enabledKey)
        try await sync()
    }

    // The foreground trigger. Quiet on every failure: a missed sync is made up by the next one,
    // since each sync covers two weeks.
    static func syncIfDue() async {
        guard isAvailable, isEnabled,
              KeychainHelper.read(forKey: Constants.Keychain.accessToken) != nil
        else { return }
        if let last = UserDefaults.standard.object(forKey: lastSyncKey) as? Date,
           Date().timeIntervalSince(last) < minimumGap {
            return
        }
        do {
            try await sync()
        } catch {
            print("[Nova] Health sync failed: \(error.localizedDescription)")
        }
    }

    static func sync() async throws {
        let calendar = Calendar.current
        let now = Date()
        guard let start = calendar.date(
            byAdding: .day, value: -(lookbackDays - 1), to: calendar.startOfDay(for: now)
        ) else { return }

        let steps = try await dailyValues(.stepCount, unit: .count(), cumulative: true, from: start, to: now)
        let energy = try await dailyValues(.activeEnergyBurned, unit: .kilocalorie(), cumulative: true, from: start, to: now)
        // Several weigh ins in a day average, which is closer to the truth than the last or first
        let weights = try await dailyValues(.bodyMass, unit: .pound(), cumulative: false, from: start, to: now)

        let dayKeys = Set(steps.keys).union(energy.keys).union(weights.keys).sorted()
        let days = dayKeys.map { key in
            HealthSyncPayload.Day(
                day: key,
                steps: steps[key].map { Int($0.rounded()) },
                activeKcal: energy[key],
                weightLb: weights[key])
        }

        let workouts = try await recentWorkouts(from: start)

        try await APIService.syncHealth(HealthSyncPayload(days: days, workouts: workouts))
        UserDefaults.standard.set(Date(), forKey: lastSyncKey)
    }

    // MARK: Reading

    // One value per calendar day, keyed by yyyy-MM-dd. A day with nothing recorded is absent.
    private static func dailyValues(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        cumulative: Bool,
        from start: Date,
        to end: Date
    ) async throws -> [String: Double] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: HKQuantityType(identifier), predicate: predicate),
            options: cumulative ? .cumulativeSum : .discreteAverage,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1))
        let collection = try await descriptor.result(for: store)

        var values: [String: Double] = [:]
        for statistics in collection.statistics() {
            let quantity = cumulative ? statistics.sumQuantity() : statistics.averageQuantity()
            if let quantity {
                values[dayFormatter.string(from: statistics.startDate)] = quantity.doubleValue(for: unit)
            }
        }
        return values
    }

    private static func recentWorkouts(from start: Date) async throws -> [HealthSyncPayload.Workout] {
        let descriptor = HKSampleQueryDescriptor<HKWorkout>(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 100)
        let workouts = try await descriptor.result(for: store)

        return workouts.map { workout in
            HealthSyncPayload.Workout(
                id: workout.uuid.uuidString,
                kind: kind(of: workout.workoutActivityType),
                startedAt: workout.startDate,
                minutes: workout.duration / 60,
                distanceMi: distanceMiles(of: workout),
                kcal: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                    .sumQuantity()?.doubleValue(for: .kilocalorie()))
        }
    }

    // Which distance type a workout recorded depends on what it was
    private static func distanceMiles(of workout: HKWorkout) -> Double? {
        let identifier: HKQuantityTypeIdentifier
        switch workout.workoutActivityType {
        case .running, .walking, .hiking: identifier = .distanceWalkingRunning
        case .cycling:                    identifier = .distanceCycling
        case .swimming:                   identifier = .distanceSwimming
        default:                          return nil
        }
        return workout.statistics(for: HKQuantityType(identifier))?.sumQuantity()?.doubleValue(for: .mile())
    }

    // The words the Pi's tool knows. Anything else is "other", and Nova calls it a workout.
    private static func kind(of type: HKWorkoutActivityType) -> String {
        switch type {
        case .running:  return "running"
        case .walking:  return "walking"
        case .hiking:   return "hiking"
        case .cycling:  return "cycling"
        case .swimming: return "swimming"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "strength"
        default:        return "other"
        }
    }
}
