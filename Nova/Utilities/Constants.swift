import Foundation

enum Constants {
    enum API {
        static let baseURL = "https://miles.lethanial.com"
    }

    enum Keychain {
        static let accessToken = "com.lethanial.nova.accessToken"
        // Stored behind Face ID only, see KeychainHelper.saveBiometricProtected
        static let password = "com.lethanial.nova.password"
    }
}
