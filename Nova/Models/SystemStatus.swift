import Foundation

struct SystemStatus: Decodable {
    let status: String
    let version: String
}

// GET /status/details: what Nova reads about herself, plus whether each service is running.
// Any reading can be null when the Pi could not take it, which means unknown, never zero.
struct SystemDetails: Decodable {
    let uptimeHours: Double?
    let turnsServed: Int?
    // A median, so it can arrive fractional
    let medianLatencyMs: Double?
    let whisperModel: String?
    let activeMemories: Int?
    let coreTempF: Double?
    let voiceServiceRestarts: Int?
    let gitCommit: String?
    // Service name to running. A null value means systemctl itself could not be asked.
    let services: [String: Bool?]
}
