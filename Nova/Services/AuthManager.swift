import Combine
import Foundation

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var isAuthenticated = false

    init() {
        if let token = KeychainHelper.read(forKey: Constants.Keychain.accessToken),
           !AuthService.isExpired(token) {
            isAuthenticated = true
        }

        // Wire the 401 callback so any unauthorized response snaps back here
        APIService.onUnauthorized = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleUnauthorized()
            }
        }
    }

    func login(password: String) async throws {
        try await AuthService.login(password: password)
        isAuthenticated = true
    }

    func loginWithBiometrics() async throws {
        guard let token = KeychainHelper.read(forKey: Constants.Keychain.accessToken),
              !AuthService.isExpired(token) else {
            throw AuthError.tokenMissing
        }
        try await AuthService.authenticateWithBiometrics()
        isAuthenticated = true
    }

    func logout() {
        AuthService.logout()
        isAuthenticated = false
    }

    func handleUnauthorized() {
        AuthService.logout()
        isAuthenticated = false
    }
}
