import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case notFound
    case serverError(Int)
    case decodingError(String)
    case streamEndedEarly

    var errorDescription: String? {
        switch self {
        case .invalidURL:               return "Internal error: bad URL."
        case .unauthorized:             return "Session expired. Please log in again."
        case .notFound:                 return "Resource not found."
        case .serverError(let code):    return "Server error (\(code))."
        case .decodingError(let msg):   return "Data error: \(msg)"
        case .streamEndedEarly:         return "The reply stopped partway through."
        }
    }
}

enum APIService {

    // Set by AuthManager.init() — called whenever any request gets a 401
    static var onUnauthorized: (() -> Void)?

    // A chat turn blocks until every tool call and the Pi's own speech playback finish,
    // which can outlast URLSession's 60 second default
    private static let chatTimeout: TimeInterval = 180

    // MARK: Public endpoints

    static func fetchStatus() async throws -> SystemStatus {
        let request = try await authenticatedRequest(path: "/status")
        return try await perform(request)
    }

    static func fetchMemories(limit: Int = 50, offset: Int = 0) async throws -> MemoryPage {
        let request = try await authenticatedRequest(path: "/memories?limit=\(limit)&offset=\(offset)")
        return try await perform(request)
    }

    // Memories Nova inferred on her own and is holding until they are approved
    static func fetchPendingMemories() async throws -> [Memory] {
        let request = try await authenticatedRequest(path: "/memories/pending")
        return try await perform(request)
    }

    static func approveMemory(id: Int) async throws {
        var request = try await authenticatedRequest(path: "/memories/\(id)/approve")
        request.httpMethod = "POST"
        try await performNoContent(request)
    }

    // Deletes active and pending memories alike, so it doubles as "reject"
    static func deleteMemory(id: Int) async throws {
        var request = try await authenticatedRequest(path: "/memories/\(id)")
        request.httpMethod = "DELETE"
        try await performNoContent(request)
    }

    // offset 0 is the newest `limit` messages; rows inside a page arrive oldest first
    static func fetchHistory(limit: Int = 50, offset: Int = 0) async throws -> [Message] {
        let request = try await authenticatedRequest(path: "/history?limit=\(limit)&offset=\(offset)")
        return try await perform(request)
    }

    static func chat(text: String) async throws -> String {
        var request = try await authenticatedRequest(path: "/chat")
        request.httpMethod = "POST"
        request.timeoutInterval = chatTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // "text" tells Nova she is writing to a screen; without it she formats for a speaker
        request.httpBody = try JSONSerialization.data(withJSONObject: ["message": text, "channel": "text"])

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(response)

        // Server returns {"response": "..."}
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["response"] as? String {
            return text
        }
        throw APIError.decodingError("Unexpected response format from /chat.")
    }

    // One piece of a streamed turn. The kind rides in the SSE "event:" line rather than
    // inside the JSON, and every payload is {"text": ...}, errors included.
    enum ChatEvent: Sendable {
        case delta(String)    // reply text as Nova writes it
        case reset            // drop everything streamed so far and start the reply over
        case done(String)     // the whole reply, exactly as the Pi saved it to history
        case failure(String)  // the turn broke on the Pi. It is finished either way.
    }

    // The same turn as chat(text:), delivered as it is written. The Pi runs the turn to the
    // end whatever happens to this connection, so a dropped stream is a lost view of a turn
    // that still happened, never a turn that did not run.
    static func chatStream(text: String) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream<ChatEvent, Error> { continuation in
            let work = Task {
                do {
                    var request = try await authenticatedRequest(path: "/chat/stream")
                    request.httpMethod = "POST"
                    request.timeoutInterval = chatTimeout
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONSerialization.data(withJSONObject: ["message": text, "channel": "text"])

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    try checkStatus(response)

                    // The kind named by the last "event:" line, which the next "data:" line belongs to
                    var kind = ""
                    for try await line in bytes.lines {
                        // A blank line ends one event, and a line opening with a colon is a
                        // comment: the server sends ": keep-alive" every 15 seconds so a long
                        // tool call cannot look like a dead connection to Cloudflare.
                        if line.isEmpty { kind = ""; continue }
                        if line.hasPrefix(":") { continue }

                        if line.hasPrefix("event:") {
                            kind = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                            continue
                        }
                        guard line.hasPrefix("data:") else { continue }

                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        guard let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                              let value = object["text"] as? String else { continue }

                        switch kind {
                        case "delta":
                            continuation.yield(.delta(value))
                        case "reset":
                            continuation.yield(.reset)
                        case "done":
                            continuation.yield(.done(value))
                            continuation.finish()
                            return
                        case "error":
                            continuation.yield(.failure(value))
                            continuation.finish()
                            return
                        default:
                            continue
                        }
                    }

                    // The body ended without done or error, so the reply was cut off in transit
                    continuation.finish(throwing: APIError.streamEndedEarly)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Leaving the chat screen mid turn closes the connection instead of reading
            // a reply into a stream nobody is consuming
            continuation.onTermination = { _ in work.cancel() }
        }
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

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let reason = "\(error)"
            print("[Nova] Decode error for \(T.self): \(reason)")
            throw APIError.decodingError(reason)
        }
    }

    // Sends a request whose response body the app has no use for, and only checks status
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
