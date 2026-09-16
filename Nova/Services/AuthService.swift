import Foundation
import LocalAuthentication

// Errors that AuthService can produce, shown directly in the UI
enum AuthError: LocalizedError {
    case invalidURL
    case invalidCredentials
    case networkError(String)
    case tokenMissing
    case tokenExpired
    case biometricsFailed
    case savedPasswordRejected

    var errorDescription: String? {
        switch self {
        case .invalidURL:               return "Internal error: bad URL."
        case .invalidCredentials:       return "Incorrect password."
        case .networkError(let msg):    return "Network error: \(msg)"
        case .tokenMissing:             return "No saved session. Please log in."
        case .tokenExpired:             return "Session expired. Log in with your password."
        case .biometricsFailed:         return "Face ID failed. Please log in."
        case .savedPasswordRejected:    return "Your saved password no longer works. Log in with your password."
        }
    }
}

// Matches the JSON shape of both /auth/login and /auth/refresh
private struct TokenResponse: Decodable {
    let accessToken: String
}

enum AuthService {

    // Tokens last 60 minutes and the server only renews one that is still valid,
    // so renewal has to happen before expiry rather than after it
    private static let refreshWindow: TimeInterval = 10 * 60

    // Send password to server, store the access token in Keychain on success
    static func login(password: String) async throws {
        guard let url = URL(string: "\(Constants.API.baseURL)/auth/login") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["password": password])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AuthError.networkError("No HTTP response.")
        }

        if http.statusCode == 401 {
            throw AuthError.invalidCredentials
        }

        guard http.statusCode == 200 else {
            throw AuthError.networkError("Status \(http.statusCode).")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let body = try decoder.decode(TokenResponse.self, from: data)

        KeychainHelper.save(body.accessToken, forKey: Constants.Keychain.accessToken)
    }

    // Trade a still valid access token for one with a fresh hour on it.
    // There is no refresh token on this backend, so an expired token cannot be renewed.
    @discardableResult
    static func refreshAccessToken(using token: String) async throws -> String {
        guard let url = URL(string: "\(Constants.API.baseURL)/auth/refresh") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AuthError.networkError("No HTTP response.")
        }

        if http.statusCode == 401 {
            throw AuthError.tokenExpired
        }

        guard http.statusCode == 200 else {
            throw AuthError.networkError("Status \(http.statusCode).")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let body = try decoder.decode(TokenResponse.self, from: data)

        KeychainHelper.save(body.accessToken, forKey: Constants.Keychain.accessToken)
        return body.accessToken
    }

    // Returns a usable access token, renewing it when it is close to expiring
    static func getValidAccessToken() async throws -> String {
        guard let token = KeychainHelper.read(forKey: Constants.Keychain.accessToken),
              let expiry = expirationDate(of: token),
              expiry > Date()
        else {
            // Nothing is left to renew with. Without this the UI stays logged in
            // while every request fails, because no request ever reaches a 401.
            APIService.onUnauthorized?()
            throw AuthError.tokenExpired
        }

        if expiry.timeIntervalSinceNow < refreshWindow {
            // A failed renewal is not fatal while the current token still works
            if let fresh = try? await refreshAccessToken(using: token) {
                return fresh
            }
        }

        return token
    }

    // Clear the stored session, used on logout or after a hard auth failure
    static func logout() {
        KeychainHelper.delete(forKey: Constants.Keychain.accessToken)
    }

    // Prompts FaceID. Throws biometricsFailed if the user cancels or fails.
    // Returns silently if the device does not support biometrics.
    static func authenticateWithBiometrics() async throws {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Device has no biometrics enrolled — skip silently
            return
        }

        let success = try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Authenticate to access Nova"
        )

        if !success {
            throw AuthError.biometricsFailed
        }
    }

    static func isExpired(_ token: String) -> Bool {
        guard let expiry = expirationDate(of: token) else { return true }
        return expiry <= Date()
    }

    // Reads the exp claim out of a JWT without verifying it; the server does the verifying
    static func expirationDate(of token: String) -> Date? {
        // JWT is three base64url segments separated by dots: header.payload.signature
        let segments = token.split(separator: ".")
        guard segments.count == 3 else { return nil }

        // Base64url uses - and _ instead of + and /; pad to a multiple of 4
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let payloadData = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let exp = json["exp"] as? TimeInterval
        else { return nil }

        // exp is a Unix timestamp in seconds
        return Date(timeIntervalSince1970: exp)
    }
}
