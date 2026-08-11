import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case notFound
    case serverError(Int)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:               return "Internal error: bad URL."
        case .unauthorized:             return "Session expired. Please log in again."
        case .notFound:                 return "Resource not found."
        case .serverError(let code):    return "Server error (\(code))."
        // Already a complete sentence from readableDecodingMessage, so no prefix.
        case .decodingError(let msg):   return msg
        }
    }
}

enum APIService {

    // Set by AuthManager.init() — called whenever any request gets a 401
    static var onUnauthorized: (() -> Void)?

    // MARK: Public endpoints

    static func fetchStatus() async throws -> SystemStatus {
        let request = try await authenticatedRequest(path: "/status")
        return try await perform(request)
    }

    // Returns the whole envelope rather than just the page, because the
    // caller needs total to show a real count and to know whether another
    // page exists. Page size is 20 to match the History tab.
    static func fetchMemories(limit: Int = 20, offset: Int = 0) async throws -> MemoriesResponse {
        let request = try await authenticatedRequest(path: "/memories?limit=\(limit)&offset=\(offset)")
        return try await perform(request)
    }

    static func deleteMemory(id: Int) async throws {
        var request = try await authenticatedRequest(path: "/memories/\(id)")
        request.httpMethod = "DELETE"
        try await performNoContent(request)
    }

    // The server takes limit and offset. It never accepted page, and FastAPI
    // drops unknown query params silently, so the old page argument was being
    // thrown away and every call returned the same first rows.
    static func fetchHistory(limit: Int = 20, offset: Int = 0) async throws -> [Message] {
        let request = try await authenticatedRequest(path: "/history?limit=\(limit)&offset=\(offset)")
        return try await perform(request)
    }

    static func chat(text: String) async throws -> String {
        var request = try await authenticatedRequest(path: "/chat")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["message": text])

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(response)

        // Server returns {"response": "..."}
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["response"] as? String {
            return text
        }
        throw APIError.decodingError("Unexpected response format from /chat.")
    }

    // MARK: Private helpers

    // Builds a GET URLRequest with the Authorization header already attached
    private static func authenticatedRequest(path: String) async throws -> URLRequest {
        guard let url = URL(string: "\(Constants.API.baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        let token = try await AuthService.getValidAccessToken()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    // Sends a request and decodes the JSON response body into type T
    private static func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)

        try checkStatus(response)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            let formatter = ISO8601DateFormatter()
            // Try with fractional seconds first (server sends microseconds)
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            // Fallback for dates without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }

            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "Cannot parse date: \(string)")
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let endpoint = request.url?.path ?? "The server"
            // Raw error to the console for debugging, plain sentence to the UI.
            print("[Nova] Decode error for \(T.self) at \(endpoint): \(error)")
            throw APIError.decodingError(readableDecodingMessage(error, endpoint: endpoint))
        }
    }

    // Turns a DecodingError into a sentence that names what broke and where.
    // A backend shape change should tell you which field moved, not print a
    // wall of Swift internals into the middle of the screen.
    private static func readableDecodingMessage(_ error: Error, endpoint: String) -> String {
        guard let decodingError = error as? DecodingError else {
            return "\(endpoint) returned data the app could not read."
        }

        switch decodingError {
        case .keyNotFound(let key, let context):
            let at = Self.describe(context.codingPath).map { " at \($0)" } ?? ""
            return "\(endpoint) is missing the field \"\(key.stringValue)\"\(at). "
                 + "The app and the server disagree about this response."

        case .typeMismatch(let expected, let context):
            let subject = Self.describe(context.codingPath) ?? "the response"
            return "\(endpoint) sent the wrong type for \(subject). "
                 + "The app expected \(expected)."

        case .valueNotFound(let expected, let context):
            let subject = Self.describe(context.codingPath) ?? "the response"
            return "\(endpoint) sent null for \(subject), which the app requires "
                 + "to be \(expected). Marking that property optional would fix it."

        case .dataCorrupted(let context):
            let at = Self.describe(context.codingPath).map { " at \($0)" } ?? ""
            return "\(endpoint) sent a value the app could not parse\(at). "
                 + context.debugDescription

        @unknown default:
            return "\(endpoint) returned an unreadable response."
        }
    }

    // Renders a coding path the way you would write it in Swift, so
    // memories[0].content instead of an array of opaque CodingKey values.
    // Returns nil for the root, where there is no meaningful location.
    private static func describe(_ path: [CodingKey]) -> String? {
        guard !path.isEmpty else { return nil }

        return path
            .map { $0.intValue.map { index in "[\(index)]" } ?? $0.stringValue }
            .joined(separator: ".")
            .replacingOccurrences(of: ".[", with: "[")
    }

    // Sends a request that returns no body (204 No Content), just checks status
    private static func performNoContent(_ request: URLRequest) async throws {
        let (_, response) = try await URLSession.shared.data(for: request)
        try checkStatus(response)
    }

    // Converts HTTP status codes into typed errors
    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }

        switch http.statusCode {
        case 200...299:     return
        case 401:
            onUnauthorized?()
            throw APIError.unauthorized
        case 404:           throw APIError.notFound
        default:            throw APIError.serverError(http.statusCode)
        }
    }
}
