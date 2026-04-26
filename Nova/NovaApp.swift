import SwiftUI

@main
struct NovaApp: App {
    @State private var isAuthenticated = false

    var body: some Scene {
        WindowGroup {
            if isAuthenticated {
                MainTabView(onLogout: handleLogout)
            } else {
                LoginView(onLoginSuccess: handleLoginSuccess)
                    .task { checkExistingSession() }
            }
        }
    }

    private func checkExistingSession() {
        // If a non-expired access token already exists in the Keychain, skip login
        guard let token = KeychainHelper.read(forKey: Constants.Keychain.accessToken) else { return }
        if !AuthService.isExpired(token) {
            isAuthenticated = true
        }
    }

    private func handleLoginSuccess() {
        isAuthenticated = true
    }

    private func handleLogout() {
        AuthService.logout()
        isAuthenticated = false
    }
}
