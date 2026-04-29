//
//  Keychain.swift
//  aau-sw8-ios
//
//  Created by jimpo on 28/04/26.
//

import Foundation
import Security

enum Keychain {
    private static let service = "dk.aau.sw8.ariadne"
    private static let account = "auth.jwt"

    static func saveJWT(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func loadJWT() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    static func deleteJWT() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension URLRequest {
    /// Attach the Keychain-stored JWT as a Bearer token if present. Service
    /// callers invoke this right after setting X-Api-Key — in shadow mode
    /// (no JWT in Keychain) it is a no-op.
    mutating func attachBearer() {
        if let token = Keychain.loadJWT() {
            setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}
