import Foundation

struct Message: Decodable, Identifiable {
    let id: UUID
    let role: String
    let content: String
    let createdAt: String?
    let sourceDevice: String?
    // Parsed once at decode so grouping a long history by day does not reparse every render
    let date: Date?

    private enum CodingKeys: String, CodingKey {
        case role, content, createdAt, sourceDevice
    }

    init(from decoder: Decoder) throws {
        id = UUID()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role         = try container.decode(String.self, forKey: .role)
        content      = try container.decode(String.self, forKey: .content)
        createdAt    = try container.decodeIfPresent(String.self, forKey: .createdAt)
        sourceDevice = try container.decodeIfPresent(String.self, forKey: .sourceDevice)
        date         = ServerDate.parse(createdAt)
    }

    var isUser: Bool { role == "user" }

    // "pi" is the room microphone and speaker; everything sent through the server is "app"
    var isFromRoom: Bool { sourceDevice == "pi" }
}
