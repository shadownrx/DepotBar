import XCTest

@testable import DepotBar

// MARK: - Token precedence (`DEPOT_TOKEN` env wins, else Keychain)

final class TokenResolveTests: XCTestCase {
    func testEnvWinsOverStoredToken() {
        XCTAssertEqual(
            TokenAuth.resolve(keychainToken: "stored", environment: ["DEPOT_TOKEN": "env"]),
            "env"
        )
    }

    func testStoredTokenUsedWhenEnvAbsent() {
        XCTAssertEqual(TokenAuth.resolve(keychainToken: "stored", environment: [:]), "stored")
    }

    func testBlankEnvFallsBackToStoredToken() {
        XCTAssertEqual(
            TokenAuth.resolve(keychainToken: "stored", environment: ["DEPOT_TOKEN": "   "]),
            "stored"
        )
    }

    func testNilWhenNeitherSideHasToken() {
        XCTAssertNil(TokenAuth.resolve(keychainToken: nil, environment: [:]))
        XCTAssertNil(TokenAuth.resolve(keychainToken: "  ", environment: [:]))
    }

    func testValuesAreTrimmed() {
        XCTAssertEqual(TokenAuth.resolve(keychainToken: "  stored  ", environment: [:]), "stored")
    }
}

// MARK: - Child process environment

final class ChildEnvironmentTests: XCTestCase {
    func testTokenExportedAsDepotTokenOthersPreserved() {
        let env = TokenAuth.childEnvironment(
            base: ["PATH": "/usr/bin", "DEPOT_ORG_ID": "org_1"], token: "tok"
        )
        XCTAssertEqual(env["DEPOT_TOKEN"], "tok")
        XCTAssertEqual(env["PATH"], "/usr/bin")
        XCTAssertEqual(env["DEPOT_ORG_ID"], "org_1")
    }

    func testNoTokenMeansNoDepotTokenKey() {
        // Nil token => child inherits a clean env => CLI falls back to `depot login`.
        let env = TokenAuth.childEnvironment(base: ["PATH": "/usr/bin"], token: nil)
        XCTAssertNil(env["DEPOT_TOKEN"])
        XCTAssertEqual(env["PATH"], "/usr/bin")
    }

    func testResolvedTokenReplacesStaleEnvValue() {
        let env = TokenAuth.childEnvironment(base: ["DEPOT_TOKEN": "stale"], token: "fresh")
        XCTAssertEqual(env["DEPOT_TOKEN"], "fresh")
    }

    func testBlankTokenIsNotExported() {
        let env = TokenAuth.childEnvironment(base: [:], token: "   ")
        XCTAssertNil(env["DEPOT_TOKEN"])
    }
}

// MARK: - In-memory storage seam

final class InMemoryStorageTests: XCTestCase {
    func testRoundTripTrimsWhitespace() throws {
        let storage = InMemoryTokenStorage()
        XCTAssertNil(try storage.load())
        try storage.save("  tok  ")
        XCTAssertEqual(try storage.load(), "tok")
        try storage.delete()
        XCTAssertNil(try storage.load())
    }

    func testRejectsBlankTokens() {
        let storage = InMemoryTokenStorage()
        XCTAssertThrowsError(try storage.save("   "))
    }
}
