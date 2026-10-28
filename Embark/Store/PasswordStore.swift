import Foundation
import LocalAuthentication
import Observation
import Security

/// Saved passwords, kept in the macOS Keychain as internet passwords, like Safari's. Each one
/// is tagged with its profile (the security domain), so profiles never see each other's logins.
/// Keychain Access lists them under "Embark".
@MainActor
@Observable
final class PasswordStore {
    /// Every saved login, without passwords. Loaded on first use.
    private(set) var logins: [SavedLogin] = []
    @ObservationIgnored private var loaded = false
    /// Sites the person said never to save passwords for.
    private(set) var neverSaveHosts: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "NeverSavePasswords") ?? [])

    /// Marks Embark's items, so other apps' passwords never show up here.
    private static let creator = NSNumber(value: 0x454D_424B as UInt32)  // 'EMBK'

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        reload()
    }

    func reload() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrCreator as String: Self.creator,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { logins = []; return }
        logins = items.compactMap { item in
            guard let host = item[kSecAttrServer as String] as? String,
                  let domain = item[kSecAttrSecurityDomain as String] as? String,
                  let profileID = UUID(uuidString: domain) else { return nil }
            return SavedLogin(host: host, username: item[kSecAttrAccount as String] as? String ?? "", profileID: profileID)
        }
        .sorted { ($0.host, $0.username) < ($1.host, $1.username) }
    }

    func all(for profileID: Profile.ID) -> [SavedLogin] {
        loadIfNeeded()
        return logins.filter { $0.profileID == profileID }
    }

    func logins(for host: String, profileID: Profile.ID) -> [SavedLogin] {
        loadIfNeeded()
        return logins.filter { $0.host == host && $0.profileID == profileID }
    }

    private func baseQuery(host: String, username: String, profileID: Profile.ID) -> [String: Any] {
        [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrCreator as String: Self.creator,
            kSecAttrServer as String: host,
            kSecAttrAccount as String: username,
            kSecAttrSecurityDomain as String: profileID.uuidString,
        ]
    }

    func password(for login: SavedLogin) -> String? {
        var query = baseQuery(host: login.host, username: login.username, profileID: login.profileID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Adds the login, or changes its password if it's saved already.
    @discardableResult
    func save(host: String, username: String, password: String, profileID: Profile.ID) -> Bool {
        let query = baseQuery(host: host, username: username, profileID: profileID)
        let data = Data(password.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrProtocol as String] = kSecAttrProtocolHTTPS
            item[kSecAttrLabel as String] = host
            item[kSecAttrComment as String] = "Saved by Embark"
            status = SecItemAdd(item as CFDictionary, nil)
        }
        reload()
        return status == errSecSuccess
    }

    func delete(_ login: SavedLogin) {
        SecItemDelete(baseQuery(host: login.host, username: login.username, profileID: login.profileID) as CFDictionary)
        reload()
    }

    /// Deletes a profile's passwords along with the profile.
    func removeProfile(_ profileID: Profile.ID) {
        for login in all(for: profileID) {
            SecItemDelete(baseQuery(host: login.host, username: login.username, profileID: profileID) as CFDictionary)
        }
        reload()
    }

    func neverSave(_ host: String) {
        neverSaveHosts.insert(host)
        UserDefaults.standard.set(Array(neverSaveHosts).sorted(), forKey: "NeverSavePasswords")
    }

    func allowSaving(_ host: String) {
        neverSaveHosts.remove(host)
        UserDefaults.standard.set(Array(neverSaveHosts).sorted(), forKey: "NeverSavePasswords")
    }

    /// Adds rows from a CSV export. Returns how many were saved.
    func importCSV(_ text: String, into profileID: Profile.ID) -> Int {
        var count = 0
        for row in PasswordCSV.parse(text) {
            guard let host = LoginHost.of(row.url) else { continue }
            if save(host: host, username: row.username, password: row.password, profileID: profileID) { count += 1 }
        }
        return count
    }

    func exportCSV(for profileID: Profile.ID) -> String {
        PasswordCSV.export(all(for: profileID).compactMap { login in
            password(for: login).map { (host: login.host, username: login.username, password: $0) }
        })
    }

    /// Touch ID or the Mac's password before a password is shown, copied or exported.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return true }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
