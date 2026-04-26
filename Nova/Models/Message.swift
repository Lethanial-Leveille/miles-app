import Foundation

struct Message: Decodable, Identifiable {
    let id: UUID
    let role: String
    let content: String
    let createdAt: String?
    let sourceDevice: String?

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
    }
}
