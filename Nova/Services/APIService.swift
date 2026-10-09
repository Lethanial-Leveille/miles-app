import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case notFound
    case serverError(Int)
    case decodingError(String)
    case streamEndedEarly
    // The server refused and said why, like "That memory is already stored"
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:               return "Internal error: bad URL."
        case .unauthorized:             return "Session expired. Please log in again."
        case .notFound:                 return "Resource not found."
        case .serverError(let code):    return "Server error (\(code))."
        case .decodingError(let msg):   return "Data error: \(msg)"
        case .streamEndedEarly:         return "The reply stopped partway through."
        case .rejected(let reason):     return reason
        }
    }
}

enum APIService {

    // Set by AuthManager.init() — called whenever any request gets a 401
    static var onUnauthorized: (() -> Void)?

    // A chat turn blocks until every tool call finishes, which can outlast URLSession's
    // 60 second default
    private static let chatTimeout: TimeInterval = 180
    // Synthesis runs about a second to first audio, and the route sends the file whole
    private static let speakTimeout: TimeInterval = 60

    // MARK: Public endpoints

    // Uptime, temperature, latency and whether each service runs
    static func fetchStatusDetails() async throws -> SystemDetails {
        let request = try await authenticatedRequest(path: "/status/details")
        return try await perform(request)
    }

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

    // Stored exactly as typed, explicit and active. The server answers 409 for a duplicate.
    static func addMemory(content: String) async throws {
        let request = try await jsonRequest(path: "/memories", method: "POST", body: ["content": content])
        try await performNoContent(request)
    }

    // An edit supersedes the memory rather than rewriting it, so the id can change and the
    // old wording stays readable through fetchMemoryHistory. Editing a pending one approves it.
    static func editMemory(id: Int, content: String) async throws -> MemoryEdit {
        let request = try await jsonRequest(path: "/memories/\(id)", method: "PATCH", body: ["content": content])
        return try await perform(request)
    }

    // What the memory says now and every wording it replaced, newest first
    static func fetchMemoryHistory(id: Int) async throws -> [MemoryVersion] {
        let request = try await authenticatedRequest(path: "/memories/\(id)/history")
        return try await perform(request)
    }

    // Pairs of stored memories that read alike, closest first. Pairs already judged
    // "keep both" never come back.
    static func fetchSimilarMemories() async throws -> [MemoryPair] {
        let request = try await authenticatedRequest(path: "/memories/similar")
        let answer: MemoryPairs = try await perform(request)
        return answer.pairs
    }

    // Remembers that these two are different facts, so the pair is never offered again.
    // Order does not matter.
    static func dismissSimilar(aID: Int, bID: Int) async throws {
        let request = try await jsonRequest(path: "/memories/similar/dismiss", method: "POST",
                                            body: ["a_id": aID, "b_id": bID])
        try await performNoContent(request)
    }

    // One sentence holding both, written by Claude on the Pi. Stores nothing, and takes a
    // few seconds.
    static func draftMerge(aID: Int, bID: Int) async throws -> MergeDraft {
        let request = try await jsonRequest(path: "/memories/merge/draft", method: "POST",
                                            body: ["a_id": aID, "b_id": bID])
        return try await perform(request)
    }

    // keep is superseded by content, so its history keeps the old wording, and drop is
    // deleted. All or nothing on the Pi. The result has a new id, so reload rather than patch.
    static func mergeMemories(keepID: Int, dropID: Int, content: String) async throws -> MergeResult {
        let request = try await jsonRequest(path: "/memories/merge", method: "POST",
                                            body: ["keep_id": keepID, "drop_id": dropID, "content": content])
        return try await perform(request)
    }

    // Timers and reminders together, soonest first, told apart by kind
    static func fetchReminders() async throws -> [Reminder] {
        let request = try await authenticatedRequest(path: "/reminders")
        return try await perform(request)
    }

    static func cancelReminder(id: Int) async throws {
        var request = try await authenticatedRequest(path: "/reminders/\(id)")
        request.httpMethod = "DELETE"
        try await performNoContent(request)
    }

    // From the start of today, so this morning's events still show
    static func fetchCalendar(days: Int = 7) async throws -> CalendarWeek {
        let request = try await authenticatedRequest(path: "/calendar/events?days=\(days)")
        return try await perform(request)
    }

    // MILES calendar events only; anything else is a 404. A new start alone keeps the length.
    // Returns the sentence the Pi wrote about what changed.
    static func changeEvent(id: String, title: String? = nil, start: Date? = nil, end: Date? = nil) async throws -> String {
        var body: [String: Any] = [:]
        if let title { body["title"] = title }
        // With the phone's offset, so the Pi never has to guess which timezone was meant
        if let start { body["start"] = eventTimeFormatter.string(from: start) }
        if let end { body["end"] = eventTimeFormatter.string(from: end) }
        let request = try await jsonRequest(path: "/calendar/events/\(pathSegment(id))", method: "PATCH", body: body)
        let answer: CalendarResult = try await perform(request)
        return answer.result
    }

    static func deleteEvent(id: String) async throws -> String {
        var request = try await authenticatedRequest(path: "/calendar/events/\(pathSegment(id))")
        request.httpMethod = "DELETE"
        let answer: CalendarResult = try await perform(request)
        return answer.result
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

    // How the reply will be rendered, not which device asked. The Pi decides whether to play
    // a reply in the room from the device, so an app turn on voice stays silent there.
    enum Channel: String {
        case text     // written for a screen, markdown allowed
        case voice    // written to be heard: no markdown, symbols spelled out
    }

    static func chat(text: String, channel: Channel = .text) async throws -> String {
        var request = try await authenticatedRequest(path: "/chat")
        request.httpMethod = "POST"
        request.timeoutInterval = chatTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["message": text, "channel": channel.rawValue])

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(response, data: data)

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
        case stage(String)    // what Nova is doing while a tool runs, "Checking your calendar"
        case reset            // drop everything streamed so far and start the reply over
        case done(String)     // the whole reply, exactly as the Pi saved it to history
        case failure(String)  // the turn broke on the Pi. It is finished either way.
    }

    // The same turn as chat(text:), delivered as it is written. The Pi runs the turn to the
    // end whatever happens to this connection, so a dropped stream is a lost view of a turn
    // that still happened, never a turn that did not run.
    static func chatStream(text: String, channel: Channel = .text) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream<ChatEvent, Error> { continuation in
            let work = Task {
                do {
                    var request = try await authenticatedRequest(path: "/chat/stream")
                    request.httpMethod = "POST"
                    request.timeoutInterval = chatTimeout
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONSerialization.data(withJSONObject: ["message": text, "channel": channel.rawValue])

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    // A refusal is a short JSON body, not a stream, so read it whole for its reason
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        try checkStatus(response, data: body)
                    }

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
                        case "stage":
                            continuation.yield(.stage(value))
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

    // A finished reply in Nova's own voice, as mp3. The Pi renders it with the same voice,
    // model and pronunciation table as the room speaker, and synthesizes the whole reply in
    // one request because eleven_v3 voices each request separately: sentence by sentence she
    // would sound like a different speaker partway through. 413 over 2000 characters, 502
    // when ElevenLabs fails.
    static func speak(text: String) async throws -> Data {
        var request = try await jsonRequest(path: "/speak", method: "POST", body: ["text": text])
        request.timeoutInterval = speakTimeout
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(response, data: data)
        return data
    }

    // MARK: Private helpers

    private struct CalendarResult: Decodable {
        let result: String
    }

    private static let eventTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter
    }()

    // Google event ids are letters and digits today, but an id is not ours to trust in a path
    private static func pathSegment(_ raw: String) -> String {
        raw.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? raw
    }

    // A request carrying a JSON body, for the routes that create or change something
    private static func jsonRequest(path: String, method: String, body: [String: Any]) async throws -> URLRequest {
        var request = try await authenticatedRequest(path: path)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

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

        try checkStatus(response, data: data)

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
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(response, data: data)
    }

    // Converts HTTP status codes into typed errors. FastAPI puts its reason in "detail",
    // and that sentence is more use on screen than a bare status code.
    private static func checkStatus(_ response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else { return }

        switch http.statusCode {
        case 200...299:     return
        case 401:
            onUnauthorized?()
            throw APIError.unauthorized
        default:
            if let data,
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = object["detail"] as? String, !detail.isEmpty {
                throw APIError.rejected(detail)
            }
            if http.statusCode == 404 { throw APIError.notFound }
            throw APIError.serverError(http.statusCode)
        }
    }
}
