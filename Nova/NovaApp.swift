import SwiftUI

@main
struct NovaApp: App {
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
