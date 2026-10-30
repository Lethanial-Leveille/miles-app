import SwiftUI
import UIKit
import UserNotifications

// Push notifications: asking iOS for permission, learning this phone's APNs token, and telling
// the Pi about it so reminders and timers reach the phone and not only the room.
//
// The order of events matters, because the three can happen in any order on a launch:
//   1. The user is logged in, so enable() asks permission and asks iOS to register.
//   2. iOS answers later with a token, through AppDelegate.
//   3. The token goes to the Pi, which needs a login to accept it.
// Steps 2 and 3 both end in syncToken(), which does nothing until it has both a token and a
// login, so whichever arrives last is the one that sends.
enum PushService {

    private static let tokenKey = "pushDeviceToken"

    // Which Apple host the Pi should send this phone's pushes to. A build run from Xcode in
    // Debug is signed for the sandbox host; an archive sent to TestFlight is signed for
    // production, and a token is refused by the wrong one. A Release build run straight from
    // Xcode is signed for sandbox but would say production here, so run Xcode builds as Debug.
    static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    // Asks permission (iOS only shows the prompt the first time) and then registers for a token.
    // Called on every login, because Apple wants registration repeated each launch: the token is
    // allowed to change.
    static func enable() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    // True when the user turned notifications off for Nova in iOS Settings, which nothing the
    // app or the Pi does can undo
    static func permissionDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    // iOS hands over raw bytes. APNs and the Pi both use the hex spelling of them.
    static func didReceive(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: tokenKey)
        Task { await syncToken() }
    }

    // Sends the token to the Pi. Silent when there is no login yet, since the login calls enable()
    // and that brings the token back through here.
    static func syncToken() async {
        guard let token = UserDefaults.standard.string(forKey: tokenKey),
              KeychainHelper.read(forKey: Constants.Keychain.accessToken) != nil
        else { return }
        do {
            try await APIService.registerPushDevice(
                token: token, environment: environment, deviceName: UIDevice.current.name)
        } catch {
            print("[Nova] Push registration failed: \(error.localizedDescription)")
        }
    }

    // Called before logging out, while the login still works, so a phone nobody is signed in on
    // stops receiving Nova's messages. Best effort: a failure must not trap anyone logged in.
    static func unregister() async {
        guard let token = UserDefaults.standard.string(forKey: tokenKey) else { return }
        try? await APIService.unregisterPushDevice(token: token)
    }

    // Asks the Pi to send a notification now, and returns how many phones Apple accepted it for
    static func sendTest() async throws -> Int {
        try await APIService.sendTestPush()
    }
}

// UIKit still owns the callbacks for the push token, and SwiftUI has no way to receive them
// without an app delegate. NovaApp attaches this one with UIApplicationDelegateAdaptor.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushService.didReceive(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Fails on a simulator without a signed-in Apple ID, and on a build with no push entitlement
        print("[Nova] Could not register for push: \(error.localizedDescription)")
    }

    // iOS stays quiet about a notification that arrives while its app is open, unless told
    // otherwise. A reminder that comes due while Nova is on screen should still show.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
