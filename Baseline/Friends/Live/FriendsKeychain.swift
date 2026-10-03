import Foundation
import Security

/// The signed-in Supabase session, the only Friends secret on the phone.
struct FriendsStoredSession: Codable, Equatable, Sendable {
    var access: String
    var refresh: String
    var expiresAt: Date
    var userID: UUID
}

/// One generic-password item: this device only, after first unlock, never synchronised to iCloud Keychain.
/// The service name is injectable so tests never touch the app's real item.
struct FriendsKeychain: Sendable {
    static let defaultService = "com.patrickschmidt.baseline.friends"
    let service: String
    let account = "session"

    init(service: String = FriendsKeychain.defaultService) { self.service = service }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: kCFBooleanFalse as Any]
    }

    func load() -> FriendsStoredSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(FriendsStoredSession.self, from: data)
    }

    @discardableResult
    func save(_ session: FriendsStoredSession) -> Bool {
        guard let data = try? JSONEncoder().encode(session) else { return false }
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = baseQuery
        for (k, v) in attributes { add[k] = v }
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    // MARK: - Reinstall

    /// Marks this install in UserDefaults. Deleting the app deletes its UserDefaults but NOT its Keychain items, so
    /// without the marker a reinstall would silently restore the old session and resume uploading to friends.
    static let installMarkerKey = "baseline.friends.installMarker"

    /// Local keys only a set-up install writes (`FriendsStore.consentShownKey` and `.digestKey`). Their presence
    /// without the marker means an update from a build that predates the marker, not a reinstall.
    static let installEvidenceKeys = ["baseline.friends.consentShown", "baseline.friends.uploadDigest"]

    /// Called before the live backend is made. On the first launch of an install (no marker yet) a session left by a
    /// previous install is deleted, so the person signs in again on purpose; then the marker is set. Returns true
    /// when it cleared.
    @discardableResult
    func clearIfNewInstall(_ defaults: UserDefaults) -> Bool {
        guard !defaults.bool(forKey: Self.installMarkerKey) else { return false }
        defaults.set(true, forKey: Self.installMarkerKey)
        guard !Self.installEvidenceKeys.contains(where: { defaults.object(forKey: $0) != nil }) else { return false }
        clear()
        return true
    }
}
