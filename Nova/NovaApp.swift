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
        guard let token = KeychainHelper.read(forKey: Constants.Keychain.accessToken),
              !AuthService.isExpired(token)
        else { return }

        // Token exists and is valid — require FaceID before granting access
        Task {
            do {
                try await AuthService.authenticateWithBiometrics()
                isAuthenticated = true
            } catch {
                // FaceID failed or was cancelled — stay on login screen
            }
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
