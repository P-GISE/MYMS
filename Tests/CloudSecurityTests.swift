import XCTest
import Security
@testable import MYMS

final class CloudSecurityTests: XCTestCase {
    func testRequestsCannotSendCredentialsToAnotherOrigin() throws {
        for path in ["@evil.example/auth/v1/token", "https://evil.example/", "//evil.example/", "/\\evil.example/", "/rest/v1/profiles#fragment", "/auth/v1/token\nInjected: true"] {
            XCTAssertThrowsError(try MYMSCloud.makeRequest(path, token: "test-token"), path)
        }
        let request = try MYMSCloud.makeRequest("/rest/v1/workout_plans?select=id", token: "test-token")
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.url?.host, URL(string: MYMSCloud.url)?.host)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertFalse(MYMSCloud.isTrustedURL(URL(string: "https://evil.example/rest/v1/profiles")))
        XCTAssertFalse(MYMSCloud.isTrustedURL(URL(string: "http://pppidannfctewwtshspw.supabase.co/rest/v1/profiles")))
        XCTAssertFalse(MYMSCloud.isTrustedURL(URL(string: MYMSCloud.url + ":444/rest/v1/profiles")))
        XCTAssertFalse(MYMSCloud.isTrustedURL(URL(string: MYMSCloud.url + "@evil.example/rest/v1/profiles")))
    }

    func testAuthenticatedNetworkSessionHasNoPersistentCacheOrCookies() {
        let configuration = MYMSCloud.networkConfiguration()
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertFalse(configuration.httpShouldSetCookies)
    }

    func testRefreshTokenIsUpdatedInDeviceOnlyUnlockedKeychain() throws {
        let service = "edu.myms.security-test." + UUID().uuidString
        let vault = TokenVault(service: service, account: "test-only")
        defer { try? vault.remove() }
        XCTAssertNil(try vault.read())
        try vault.write("fake-refresh-one")
        try vault.write("fake-refresh-two")
        XCTAssertEqual(try vault.read(), "fake-refresh-two")
        var attributes: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: "test-only", kSecReturnAttributes as String: true
        ] as CFDictionary, &attributes)
        XCTAssertEqual(status, errSecSuccess)
        let values = try XCTUnwrap(attributes as? [String: Any])
        XCTAssertEqual(values[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertNotEqual(values[kSecAttrSynchronizable as String] as? Bool, true)
        try vault.remove()
        XCTAssertNil(try vault.read())
    }

    @MainActor func testWorkoutSnapshotUsesCompleteFileProtection() throws {
        let account = UUID()
        defer { try? WorkoutStore.deleteLocalData(for: account) }
        let store = WorkoutStore(accountID: account)
        store.plans = [Workout()]
        XCTAssertNil(store.localError)
        let url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("MYMS").appendingPathComponent(account.uuidString + ".json")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attributes[.protectionKey] as? String, FileProtectionType.complete.rawValue)
    }

    @MainActor func testSignedOutMarkerPreventsRestoringAnOldCredential() throws {
        let name = "edu.myms.security-test." + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        let vault = TokenVault(service: name, account: "test-only")
        defer { try? vault.remove(); preferences.removePersistentDomain(forName: name) }
        try vault.write("fake-refresh-old-session")
        preferences.set(true, forKey: Accounts.restoreDisabledKey)
        let accounts = Accounts(vault: vault, preferences: preferences)
        XCTAssertNil(accounts.current)
        XCTAssertFalse(accounts.restoring)
        XCTAssertNil(try vault.read())
        accounts.enterLocalMode()
        XCTAssertTrue(accounts.isLocalMode)
        accounts.signOut()
        XCTAssertTrue(preferences.bool(forKey: Accounts.restoreDisabledKey))
        XCTAssertNil(accounts.current)
    }
}
