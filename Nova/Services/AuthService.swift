import Foundation

// Errors that AuthService can produce, shown directly in the UI
enum AuthError: LocalizedError {
    case invalidURL
    case invalidCredentials
    case networkError(String)
    case tokenMissing
    case tokenExpired

    var errorDescription: String? {
        switch self {
        case .invalidURL:               return "Internal error: bad URL."
        case .invalidCredentials:       return "Incorrect password."
        case .networkError(let msg):    return "Network error: \(msg)"
        case .tokenMissing:             return "No saved session. Please log in."
        case .tokenExpired:             return "Session expired. Please log in."
        }
    }
}

// Matches the JSON shape of the /auth/login response
private struct LoginResponse: Decodable {
    let accessToken: String
    let refreshToken: String
}

// Matches the JSON shape of the /auth/refresh response
private struct RefreshResponse: Decodable {
    let accessToken: String
}

enum AuthService {

    // Send password to server, store both tokens in Keychain on success
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
        let body = try decoder.decode(LoginResponse.self, from: data)

        KeychainHelper.save(body.accessToken, forKey: Constants.Keychain.accessToken)
        KeychainHelper.save(body.refreshToken, forKey: Constants.Keychain.refreshToken)
    }

    // Use the stored refresh token to get a new access token
    static func refreshAccessToken() async throws {
        guard let refreshToken = KeychainHelper.read(forKey: Constants.Keychain.refreshToken) else {
            throw AuthError.tokenMissing
        }

        guard let url = URL(string: "\(Constants.API.baseURL)/auth/refresh") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(refreshToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AuthError.networkError("No HTTP response.")
        }

        guard http.statusCode == 200 else {
            throw AuthError.tokenExpired
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let body = try decoder.decode(RefreshResponse.self, from: data)

        KeychainHelper.save(body.accessToken, forKey: Constants.Keychain.accessToken)
    }

    // Returns a valid access token, refreshing automatically if it has expired
    static func getValidAccessToken() async throws -> String {
        if let token = KeychainHelper.read(forKey: Constants.Keychain.accessToken),
           !isExpired(token) {
            return token
        }

        // Access token is missing or expired, try refreshing
        try await refreshAccessToken()

        guard let newToken = KeychainHelper.read(forKey: Constants.Keychain.accessToken) else {
            throw AuthError.tokenMissing
        }

        return newToken
    }

    // Clear both tokens — used on logout or after a hard auth failure
    static func logout() {
        KeychainHelper.delete(forKey: Constants.Keychain.accessToken)
        KeychainHelper.delete(forKey: Constants.Keychain.refreshToken)
    }

    // Returns true if the JWT's exp claim is in the past
    static func isExpired(_ token: String) -> Bool {
        // JWT is three base64url segments separated by dots: header.payload.signature
        let segments = token.split(separator: ".")
        guard segments.count == 3 else { return true }

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
        else { return true }

        // exp is a Unix timestamp in seconds; Date() is the current time
        return Date().timeIntervalSince1970 > exp
    }
}
