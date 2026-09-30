import Foundation
import Security

// MARK: - Token storage seam (Keychain in production, in-memory in tests)

protocol TokenStorage: Sendable {
    func load() throws -> String?
    func save(_ token: String) throws
    func delete() throws
}

enum TokenStoreError: Error, Sendable {
    case keychainError(OSStatus)
    case invalidToken
}

extension TokenStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .keychainError(let status):
            return "Keychain error (\(status))"
        case .invalidToken:
            return "Token is empty"
        }
    }
}

/// Generic-password Keychain item for the Depot API token.
struct KeychainTokenStorage: TokenStorage {
    private let service = "com.facmartoni.DepotBar"
    private let account = "depot-api-token"

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else {
            throw TokenStoreError.keychainError(status)
        }
        return token
    }

    func save(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TokenStoreError.invalidToken }
        guard let data = trimmed.data(using: .utf8) else { throw TokenStoreError.invalidToken }
        var query = baseQuery()
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        var attributes: [String: Any] = [kSecValueData as String: data]
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else { throw TokenStoreError.keychainError(updateStatus) }
            return
        }
        guard status == errSecSuccess else { throw TokenStoreError.keychainError(status) }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError.keychainError(status)
        }
    }
}

/// In-memory storage for tests (never touches the Keychain).
final class InMemoryTokenStorage: TokenStorage, @unchecked Sendable {
    private var token: String?
    init(token: String? = nil) { self.token = token }
    func load() throws -> String? { token }
    func save(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TokenStoreError.invalidToken }
        self.token = trimmed
    }
    func delete() throws { token = nil }
}

// MARK: - Token resolution (pure logic, covered by tests)

enum TokenAuth {
    static let envKey = "DEPOT_TOKEN"

    /// Precedence: explicit `DEPOT_TOKEN` env var wins over the Keychain token.
    /// Blank values count as absent on both sides.
    static func resolve(keychainToken: String?, environment: [String: String]) -> String? {
        if let env = environment[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty
        {
            return env
        }
        if let stored = keychainToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !stored.isEmpty
        {
            return stored
        }
        return nil
    }

    /// Environment for the `depot` child process: the resolved token (if any)
    /// is exported as `DEPOT_TOKEN`, which the CLI prefers over `depot login`.
    /// Everything else in the base environment is preserved untouched.
    static func childEnvironment(base: [String: String], token: String?) -> [String: String] {
        var env = base
        if let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            env[envKey] = token
        }
        return env
    }
}
