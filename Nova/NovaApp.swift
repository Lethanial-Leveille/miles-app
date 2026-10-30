import SwiftUI

@main
struct NovaApp: App {
    // Push tokens arrive through UIKit callbacks that SwiftUI cannot receive on its own
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authManager = AuthManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    MainTabView()
                } else {
                    LoginView()
                        .task { await attemptBiometricResume() }
                }
            }
            .environmentObject(authManager)
            .preferredColorScheme(.dark)
            // Icon buttons have fixed frames; past this size their symbols would spill out
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { authManager.validateSession() }
            }
            // Runs at launch and again at each login, so a push token is always registered
            // for whoever is signed in
            .task(id: authManager.isAuthenticated) {
                if authManager.isAuthenticated { await PushService.enable() }
            }
        }
    }

    // On launch, try to skip the password screen if a valid token exists in Keychain
    private func attemptBiometricResume() async {
        do {
            try await authManager.loginWithBiometrics()
        } catch {
            // Token invalid or FaceID cancelled — stay on login screen
        }
    }
}
