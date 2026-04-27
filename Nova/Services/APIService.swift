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
        case .decodingError(let msg):   return "Data error: \(msg)"
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

    static func fetchMemories() async throws -> [Memory] {
        let request = try await authenticatedRequest(path: "/memories")
        return try await perform(request)
    }

    static func deleteMemory(id: String) async throws {
        var request = try await authenticatedRequest(path: "/memories/\(id)")
        request.httpMethod = "DELETE"
        try await performNoContent(request)
    }

    static func fetchHistory(page: Int = 1) async throws -> [Message] {
        let request = try await authenticatedRequest(path: "/history?page=\(page)")
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
            let reason = "\(error)"
            print("[Nova] Decode error for \(T.self): \(reason)")
            throw APIError.decodingError(reason)
        }
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
