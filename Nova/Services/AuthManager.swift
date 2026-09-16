import Combine
import Foundation
import LocalAuthentication

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
        rememberPasswordForFaceID(password)
        isAuthenticated = true
    }

    func loginWithBiometrics() async throws {
        // With a saved password, reading it back is the Face ID check, and it can start
        // a brand new session even after the hour is up
        if KeychainHelper.biometricProtectedItemExists(forKey: Constants.Keychain.password) {
            guard let password = await KeychainHelper.readBiometricProtected(
                forKey: Constants.Keychain.password,
                reason: "Unlock Nova"
            ) else {
                throw AuthError.biometricsFailed
            }
            try await resumeSession(with: password)
            isAuthenticated = true
            return
        }

        // Without one (no device passcode, or no password login on this phone yet),
        // Face ID can only unlock a session that has not expired
        guard let token = KeychainHelper.read(forKey: Constants.Keychain.accessToken) else {
            throw AuthError.tokenMissing
        }
        guard !AuthService.isExpired(token) else {
            throw AuthError.tokenExpired
        }
        try await AuthService.authenticateWithBiometrics()

        // Start every unlock with a full hour instead of whatever was left over
        _ = try? await AuthService.refreshAccessToken(using: token)
        isAuthenticated = true
    }

    // Called when the app returns to the foreground, since a token can expire while it sits in the background
    func validateSession() {
        guard isAuthenticated else { return }
        guard let token = KeychainHelper.read(forKey: Constants.Keychain.accessToken),
              !AuthService.isExpired(token)
        else {
            handleUnauthorized()
            return
        }
    }

    func logout() {
        AuthService.logout()
        // Logging out on purpose should mean Face ID cannot walk straight back in
        KeychainHelper.delete(forKey: Constants.Keychain.password)
        isAuthenticated = false
    }

    // Keeps the saved password, so Face ID on the login screen can recover the session
    func handleUnauthorized() {
        AuthService.logout()
        isAuthenticated = false
    }

    // MARK: Private

    private func resumeSession(with password: String) async throws {
        if let token = KeychainHelper.read(forKey: Constants.Keychain.accessToken),
           !AuthService.isExpired(token) {
            // A live token only needs renewing, and a failed renewal still leaves it usable
            _ = try? await AuthService.refreshAccessToken(using: token)
            return
        }

        do {
            try await AuthService.login(password: password)
        } catch AuthError.invalidCredentials {
            // The password changed on the Pi, so this copy will never work again
            KeychainHelper.delete(forKey: Constants.Keychain.password)
            throw AuthError.savedPasswordRejected
        }
    }

    private func rememberPasswordForFaceID(_ password: String) {
        guard LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return }
        KeychainHelper.saveBiometricProtected(password, forKey: Constants.Keychain.password)
    }
}
