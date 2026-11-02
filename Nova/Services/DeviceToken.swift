import Foundation

// The phone's long lived token for writes it makes in the background: where it is, and later its
// Health data. A login lasts an hour and renewing one takes Face ID, which cannot run while the
// phone is in a pocket, so a geofence crossing at 8 AM would otherwise reach a Pi that refuses it.
//
// The Pi accepts this token only on those background routes and refuses it on every other one,
// so it can never read a memory or change the calendar. Kept in the Keychain readable after the
// first unlock, which is what lets a background launch use it.
enum DeviceToken {

    // Renewed a month before it runs out, so a phone opened only now and then never holds a dead one
    private static let renewWithin: TimeInterval = 30 * 24 * 3600

    static var current: String? {
        KeychainHelper.read(forKey: Constants.Keychain.deviceToken)
    }

    // Called after every login. Asks the Pi only when there is no token or it is close to expiry.
    static func ensure() async {
        if let token = current,
           let expiry = AuthService.expirationDate(of: token),
           expiry.timeIntervalSinceNow > renewWithin {
            return
        }
        do {
            let token = try await APIService.fetchDeviceToken()
            KeychainHelper.save(token, forKey: Constants.Keychain.deviceToken)
        } catch {
            print("[Nova] Could not get a device token: \(error.localizedDescription)")
        }
    }

    // On logout, and when the Pi refuses it, so the next login fetches a fresh one
    static func forget() {
        KeychainHelper.delete(forKey: Constants.Keychain.deviceToken)
    }
}

// POST /auth/device
struct DeviceTokenResponse: Decodable {
    let accessToken: String
}
