import SwiftUI

@main
struct NovaApp: App {
    @StateObject private var authManager = AuthManager()

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
