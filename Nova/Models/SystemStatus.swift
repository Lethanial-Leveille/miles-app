import Foundation

struct SystemStatus: Decodable {
    let uptime: Double
    let version: String
    let memoryCount: Int
    let lastInteraction: Date?
}
