import Foundation
import Security

/// 令牌与会话的持久化。
///
/// MG Live 的 tocToken / swapToken 是单会话凭证（有效期约 30 分钟），优先写 Keychain：
/// - Keychain：`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`，不随 iCloud 备份漂移；
/// - UserDefaults：只保留手机号、昵称、uid 这类展示字段和设备标识。
///
/// 未签名 / TrollStore 环境下 keychain-access-groups 可能不完整，`SecItemAdd` 会返回
/// `-34018 (errSecMissingEntitlement)`。这时退回 UserDefaults 明文保存，保证冷启动不掉登录，
/// 并在 DEBUG 下打印 OSStatus，便于定位签名问题。
enum SessionStore {
    private static let service = "com.alanpfx.mgcontrol.session"
    private static let tocKey = "mg.toc"
    private static let swapKey = "mg.swap"

    // MARK: - 读写

    static func token(_ key: String) -> String? {
        guard key == tocKey || key == swapKey else { return nil }
        if let value = readKeychain(key) { return value }
        // Keychain 不可用时的兜底（迁移后旧值仍在 UserDefaults）
        let legacy = UserDefaults.standard.string(forKey: key)
        return (legacy?.isEmpty == false) ? legacy : nil
    }

    static func save(token: String, key: String) {
        guard key == tocKey || key == swapKey else { return }
        if token.isEmpty {
            deleteKeychain(key)
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        if writeKeychain(key, token) {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(token, forKey: key)
        }
    }

    static func clearTokens() {
        for key in [tocKey, swapKey] {
            deleteKeychain(key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// 旧版本把 token 写在 UserDefaults：搬到 Keychain，搬成功才删旧值，避免丢会话。
    static func migrateLegacyTokens() {
        let defaults = UserDefaults.standard
        for key in [tocKey, swapKey] {
            guard let value = defaults.string(forKey: key), !value.isEmpty else { continue }
            if readKeychain(key) == nil, writeKeychain(key, value) {
                defaults.removeObject(forKey: key)
            }
        }
    }

    // MARK: - Keychain 原语

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    private static func readKeychain(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            if status != errSecItemNotFound { log("read \(key)", status) }
            return nil
        }
        return value
    }

    /// 写入并回读校验，返回是否真正落到 Keychain。
    @discardableResult
    private static func writeKeychain(_ key: String, _ value: String) -> Bool {
        let data = Data(value.utf8)
        let query = baseQuery(key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else {
            var insert = query
            insert.merge(attributes) { _, new in new }
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess, readKeychain(key) == value else {
            log("write \(key)", status)
            return false
        }
        return true
    }

    private static func deleteKeychain(_ key: String) {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            log("delete \(key)", status)
        }
    }

    private static func log(_ action: String, _ status: OSStatus) {
        #if DEBUG
        print("[SessionStore] \(action) failed: OSStatus \(status)")
        #endif
    }
}
