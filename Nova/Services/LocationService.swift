import CoreLocation
import Foundation

// A geofence around home, so the Pi knows whether Lethanial is home or away. The room radar says
// whether anyone is in the room; this says whether he is anywhere nearby. Together they are what
// "ignore wakes while he is away, unless a guest is there" will be built on (BACKEND_TODO.md,
// "Wakes while he is away"). For now the Pi only logs the crossings, to learn how promptly and
// reliably iOS reports them before anything trusts them.
//
// CLMonitor (iOS 17) watches a named circle and reports when the phone goes in or out. If the app
// is not running, iOS relaunches it in the background to deliver the event, which only works if
// the monitor is set up again at every launch: AppDelegate calls resume() for that.
enum LocationService {

    private static let monitorName = "nova-home"
    private static let conditionID = "home"

    // Wide enough that GPS wobble indoors never reads as leaving; small enough that a walk to the
    // corner store does
    private static let radius: CLLocationDistance = 150

    private static let latitudeKey = "homeLatitude"
    private static let longitudeKey = "homeLongitude"
    private static let lastStateKey = "presenceLastState"
    private static let lastAtKey = "presenceLastAt"

    private static let manager = CLLocationManager()
    private static var monitor: CLMonitor?
    private static var listening: Task<Void, Never>?

    enum LocationError: LocalizedError {
        case denied, noFix

        var errorDescription: String? {
            switch self {
            case .denied: return "Location is off for Nova. Turn it on in iOS Settings."
            case .noFix:  return "Could not get a location fix. Try again by a window."
            }
        }
    }

    // MARK: State

    static var home: CLLocationCoordinate2D? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: latitudeKey) != nil else { return nil }
        return CLLocationCoordinate2D(latitude: defaults.double(forKey: latitudeKey),
                                      longitude: defaults.double(forKey: longitudeKey))
    }

    // Leaving home is noticed with the app closed only under Always
    static var hasAlways: Bool { manager.authorizationStatus == .authorizedAlways }

    // What the Settings row says under its title
    static func statusLine() -> String {
        guard home != nil else { return "Not set. Tap while you are at home" }
        guard hasAlways else {
            return "Set, but location is not Always, so leaving is missed. Change it in iOS Settings"
        }
        if let state = UserDefaults.standard.string(forKey: lastStateKey),
           let at = UserDefaults.standard.object(forKey: lastAtKey) as? Date {
            let word = state == "home" ? "Home" : "Away"
            return "\(word) since \(at.formatted(date: .abbreviated, time: .shortened)). Tap to reset home here"
        }
        return "Set. Watching for you to leave. Tap to reset home here"
    }

    // MARK: Setting home

    // Home is wherever the phone is when this runs, so it is tapped once, at home
    static func setHomeHere() async throws {
        try await requestWhenInUse()
        let location = try await currentLocation()
        UserDefaults.standard.set(location.coordinate.latitude, forKey: latitudeKey)
        UserDefaults.standard.set(location.coordinate.longitude, forKey: longitudeKey)
        // iOS offers Always only after When In Use, and shows that prompt once
        manager.requestAlwaysAuthorization()
        await startMonitoring()
    }

    // At every launch, foreground or background, so a crossing that woke the app is delivered
    static func resume() async {
        guard home != nil else { return }
        await startMonitoring()
    }

    // MARK: Monitoring

    private static func startMonitoring() async {
        guard let home else { return }

        let active: CLMonitor
        if let existing = monitor {
            active = existing
        } else {
            active = await CLMonitor(monitorName)
            monitor = active
        }

        // Same identifier, so setting home again replaces the circle instead of adding a second.
        // Assumed outside, so being home when it starts produces a "home" event straight away.
        await active.add(CLMonitor.CircularGeographicCondition(center: home, radius: radius),
                         identifier: conditionID, assuming: .unsatisfied)

        guard listening == nil else { return }
        listening = Task {
            do {
                for try await event in await active.events {
                    switch event.state {
                    case .satisfied:   await report("home", at: event.date)
                    case .unsatisfied: await report("away", at: event.date)
                    default:           continue
                    }
                }
            } catch {
                print("[Nova] Geofence stopped: \(error.localizedDescription)")
            }
        }
    }

    private static func report(_ state: String, at date: Date) async {
        // Kept on the phone too, so Settings can say what it last saw even if the Pi missed it
        UserDefaults.standard.set(state, forKey: lastStateKey)
        UserDefaults.standard.set(date, forKey: lastAtKey)
        do {
            try await APIService.reportPresence(state: state, at: date)
        } catch {
            print("[Nova] Could not report \(state): \(error.localizedDescription)")
        }
    }

    // MARK: Permission and a fix

    private static func requestWhenInUse() async throws {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            // The answer comes through a delegate this app has no other use for, so watch the
            // status instead: he is looking at the prompt, and a check every half second is free
            for _ in 0..<120 where manager.authorizationStatus == .notDetermined {
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        guard [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) else {
            throw LocationError.denied
        }
    }

    // The first fix within 50 metres, or the best of the first ten. The first fixes indoors can be
    // hundreds of metres off, and home is set once, so it is worth waiting a moment for a good one.
    private static func currentLocation() async throws -> CLLocation {
        var best: CLLocation?
        var seen = 0
        for try await update in CLLocationUpdate.liveUpdates() {
            guard let location = update.location, location.horizontalAccuracy >= 0 else { continue }
            if location.horizontalAccuracy <= 50 { return location }
            if best.map({ location.horizontalAccuracy < $0.horizontalAccuracy }) ?? true {
                best = location
            }
            seen += 1
            if seen >= 10, let best { return best }
        }
        if let best { return best }
        throw LocationError.noFix
    }
}
