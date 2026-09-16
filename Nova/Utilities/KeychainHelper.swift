import Foundation
import LocalAuthentication
import Security

enum KeychainHelper {

    @discardableResult
    static func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete any existing item first so SecItemAdd does not get a duplicate error
        delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrAccount as String:      key,
            kSecValueData as String:        data,
            // Accessible after first device unlock, survives app restarts and background access
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlock
        ]

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func read(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrAccount as String:  key,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }

        return string
    }

    @discardableResult
    static func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrAccount as String:  key
        ]

        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    // MARK: Face ID protected items

    // Only a successful Face ID check on this device can read the item back. It is never
    // synced or backed up, needs a device passcode, and iOS discards it if Face ID enrollment
    // changes, so someone who adds their own face cannot use it.
    @discardableResult
    static func saveBiometricProtected(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8),
              let access = SecAccessControlCreateWithFlags(
                  nil,
                  kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                  .biometryCurrentSet,
                  nil
              )
        else { return false }

        delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String:             kSecClassGenericPassword,
            kSecAttrAccount as String:       key,
            kSecValueData as String:         data,
            kSecAttrAccessControl as String: access
        ]

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    // Answers whether the item exists without showing the Face ID prompt
    static func biometricProtectedItemExists(forKey key: String) -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true

        let query: [String: Any] = [
            kSecClass as String:                    kSecClassGenericPassword,
            kSecAttrAccount as String:              key,
            kSecUseAuthenticationContext as String: context
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // A protected item that exists can answer "interaction not allowed" instead of success
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    // Shows the Face ID prompt and returns nil if it is cancelled or fails.
    // SecItemCopyMatching blocks until the prompt is answered, so it must not run on the main thread.
    static func readBiometricProtected(forKey key: String, reason: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let context = LAContext()
                context.localizedReason = reason

                let query: [String: Any] = [
                    kSecClass as String:                    kSecClassGenericPassword,
                    kSecAttrAccount as String:              key,
                    kSecReturnData as String:               true,
                    kSecMatchLimit as String:               kSecMatchLimitOne,
                    kSecUseAuthenticationContext as String: context
                ]

                var result: AnyObject?
                let status = SecItemCopyMatching(query as CFDictionary, &result)

                guard status == errSecSuccess,
                      let data = result as? Data,
                      let string = String(data: data, encoding: .utf8)
                else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: string)
            }
        }
    }
}
