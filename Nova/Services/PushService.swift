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
        registerCategories()
        UIApplication.shared.registerForRemoteNotifications()
    }

    // The Approve and Skip buttons on an approval push. Both need the phone unlocked, and both
    // open the app, because the decision is sent with his full login, which may need Face ID.
    nonisolated static let approvalCategory = "MILES_APPROVAL"
    nonisolated static let approveAction = "APPROVE"
    nonisolated static let skipAction = "SKIP"

    static func registerCategories() {
        let approve = UNNotificationAction(identifier: approveAction, title: "Approve",
                                           options: [.authenticationRequired, .foreground])
        let skip = UNNotificationAction(identifier: skipAction, title: "Skip",
                                        options: [.authenticationRequired, .foreground, .destructive])
        let category = UNNotificationCategory(identifier: approvalCategory, actions: [approve, skip],
                                              intentIdentifiers: [], options: [])
        // iOS replaces the whole set on every call, so both categories go in together.
        UNUserNotificationCenter.current().setNotificationCategories([category, watchdogCategory()])
    }

    // The Mac missed a scheduled job (the 7 PM drafts, the 9 PM summaries). Three answers, each
    // sent with his full login: run it when the Mac next checks in, ask again at 7 AM, or drop it.
    nonisolated static let watchdogCategoryID = "MILES_WATCHDOG"
    nonisolated static let retryAction = "WATCHDOG_RETRY"
    nonisolated static let remindAction = "WATCHDOG_REMIND"
    nonisolated static let skipTonightAction = "WATCHDOG_SKIP"

    private static func watchdogCategory() -> UNNotificationCategory {
        let retry = UNNotificationAction(identifier: retryAction, title: "Retry when awake",
                                         options: [.authenticationRequired, .foreground])
        let remind = UNNotificationAction(identifier: remindAction, title: "Remind me at 7 AM",
                                          options: [.authenticationRequired, .foreground])
        let skip = UNNotificationAction(identifier: skipTonightAction, title: "Skip tonight",
                                        options: [.authenticationRequired, .foreground, .destructive])
        return UNNotificationCategory(identifier: watchdogCategoryID, actions: [retry, remind, skip],
                                      intentIdentifiers: [], options: [])
    }

    static func decideWatchdog(alertID: Int, decision: String) async {
        do {
            let message = try await APIService.decideWatchdog(id: alertID, decision: decision)
            await confirm(message)
        } catch {
            await confirm("Not recorded: \(error.localizedDescription)")
        }
    }

    // One tap on one request. The result is shown as a local notification, so he knows whether
    // it went through without opening anything else.
    static func decide(approvalID: Int, approve: Bool) async {
        do {
            try await APIService.decideApproval(id: approvalID, approve: approve)
            await confirm(approve ? "Approved. The Mac will do it now." : "Skipped. Nothing will be done.")
        } catch {
            await confirm("Not recorded: \(error.localizedDescription)")
        }
        ApprovalRouter.shared.refresh()
    }

    private static func confirm(_ body: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Nova"
        content.body = body
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
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
        // A geofence crossing can be what launched the app, and is only delivered once the
        // monitor exists again
        Task { await LocationService.resume() }
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

    // A tap on an approval push: Approve or Skip decide that one request; a plain tap opens the
    // approvals screen on it.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        let info = content.userInfo
        let approvalID = (info["approval_id"] as? Int) ?? (info["approval_id"] as? NSNumber)?.intValue
        if content.categoryIdentifier == PushService.watchdogCategoryID,
           let id = (info["watchdog_id"] as? Int) ?? (info["watchdog_id"] as? NSNumber)?.intValue {
            let decision: String? = [PushService.retryAction: "retry",
                                     PushService.remindAction: "remind",
                                     PushService.skipTonightAction: "skip"][response.actionIdentifier]
            if let decision {
                await PushService.decideWatchdog(alertID: id, decision: decision)
                return
            }
        }
        if content.categoryIdentifier == PushService.approvalCategory, let id = approvalID {
            switch response.actionIdentifier {
            case PushService.approveAction:
                await PushService.decide(approvalID: id, approve: true)
                return
            case PushService.skipAction:
                await PushService.decide(approvalID: id, approve: false)
                return
            default:
                break
            }
        }
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        // A plain tap on a MILES push (not a timer or reminder): a problem opens in full; anything
        // else opens Approvals on the request it was about.
        let kind = (info["kind"] as? String) ?? content.threadIdentifier
        // A session push (the nightly review and its reminder) opens that session. It has no
        // category, so a plain tap is the only way here.
        if kind == "session" {
            let sessionID = (info["session_id"] as? Int) ?? (info["session_id"] as? NSNumber)?.intValue
            await MainActor.run {
                if let sessionID {
                    SessionRouter.shared.open(sessionID: sessionID)
                } else {
                    SessionRouter.shared.openList()
                }
            }
            return
        }
        guard ["approval", "agent", "watchdog", "login"].contains(kind)
                || content.categoryIdentifier == PushService.watchdogCategoryID else { return }
        let isError = (info["level"] as? String) == "error"
            || content.categoryIdentifier == PushService.watchdogCategoryID
        let note = PushNote(title: content.title,
                            detail: (info["detail"] as? String) ?? content.body,
                            approvalID: approvalID)
        await MainActor.run {
            if isError {
                ApprovalRouter.shared.showError(note)
            } else {
                ApprovalRouter.shared.open(approvalID: approvalID)
            }
        }
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
