import Foundation

enum Constants {
    enum API {
        static let baseURL = "https://miles.lethanial.com"
        static let webSocketURL = "wss://miles.lethanial.com/ws"
    }

    enum Keychain {
        static let accessToken = "com.lethanial.nova.accessToken"
        static let refreshToken = "com.lethanial.nova.refreshToken"
    }
}
