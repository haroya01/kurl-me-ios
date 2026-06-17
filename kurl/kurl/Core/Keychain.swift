//
//  Keychain.swift
//  kurl
//

import Foundation
import Security

/// 토큰 보관 전용 최소 Keychain 래퍼. UserDefaults 는 백업/탈옥 덤프에 노출되므로
/// 리프레시 토큰은 반드시 여기로만 들어간다.
enum Keychain {
    private static let service = "me.kurl.app"

    /// 토큰 쓰기 실패는 다음 refresh 에서 세션 유실로 이어지므로 호출부가 알아챌 수 있게 성공 여부를 돌려준다.
    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            attributes.forEach { add[$0.key] = $0.value }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        if status != errSecSuccess {
            assertionFailure("Keychain save failed for \(account): \(status)")
            return false
        }
        return true
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
