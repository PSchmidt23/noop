import XCTest
@testable import Baseline

/// `SupabaseREST` and `SupabaseFriendsBackend` against a stubbed network: the id-token exchange, proactive refresh,
/// one retry after a 401, error mapping, the delete fallback, and the Keychain item. No request leaves the process.
final class SupabaseRESTTests: XCTestCase {

    private let anonJWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiJ9.c2ln"
    private let keychain = FriendsKeychain(service: "com.patrickschmidt.baseline.friends.tests")
    private var config: FriendsConfig { FriendsConfig.make(url: "https://stub.supabase.co", key: anonJWT)! }
    private let userID = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!

    override func setUp() {
        super.setUp()
        keychain.clear()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        keychain.clear()
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func rest(now: Date = Date()) -> SupabaseREST {
        SupabaseREST(config: config, keychain: keychain,
                     session: SupabaseREST.makeSession(protocolClasses: [StubURLProtocol.self]), now: { now })
    }

    private func tokenJSON(access: String, expiresIn: Int = 3600) -> Data {
        Data("""
        {"access_token":"\(access)","token_type":"bearer","expires_in":\(expiresIn),"refresh_token":"r-\(access)",
         "user":{"id":"\(userID.uuidString.lowercased())"}}
        """.utf8)
    }

    func testIdTokenExchange_bodyAndHeaders_andKeychain() async throws {
        StubURLProtocol.handler = { _ in (200, self.tokenJSON(access: "A1")) }
        let r = rest()
        let s = try await r.signInWithIdToken(idToken: "apple-token", nonce: "raw-nonce")
        XCTAssertEqual(s.userID, userID)
        let req = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(req.url?.path, "/auth/v1/token")
        XCTAssertEqual(req.url?.query, "grant_type=id_token")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "apikey"), anonJWT)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer \(anonJWT)")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: StubURLProtocol.bodies.first ?? Data()) as? [String: String])
        XCTAssertEqual(body, ["provider": "apple", "id_token": "apple-token", "nonce": "raw-nonce"],
                       "the RAW nonce goes to Supabase; Apple signed its SHA-256")
        XCTAssertEqual(keychain.load()?.access, "A1")
        XCTAssertEqual(keychain.load()?.userID, userID)
    }

    func testProactiveRefresh_underAMinuteLeft() async throws {
        let now = Date()
        keychain.save(FriendsStoredSession(access: "OLD", refresh: "R", expiresAt: now.addingTimeInterval(30), userID: userID))
        StubURLProtocol.handler = { req in
            if req.url?.path == "/auth/v1/token" { return (200, self.tokenJSON(access: "NEW")) }
            return (200, Data("{\"accepted\":1,\"dropped\":0}".utf8))
        }
        _ = try await rest(now: now).rpc("upload")
        XCTAssertEqual(StubURLProtocol.requests.map { $0.url?.path }, ["/auth/v1/token", "/rest/v1/rpc/upload"])
        XCTAssertEqual(StubURLProtocol.requests.first?.url?.query, "grant_type=refresh_token")
        XCTAssertEqual(StubURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer NEW")
    }

    func test401_refreshesOnce_thenRetries() async throws {
        keychain.save(FriendsStoredSession(access: "STALE", refresh: "R", expiresAt: Date().addingTimeInterval(3000), userID: userID))
        StubURLProtocol.handler = { req in
            if req.url?.path == "/auth/v1/token" { return (200, self.tokenJSON(access: "FRESH")) }
            if req.value(forHTTPHeaderField: "Authorization") == "Bearer STALE" { return (401, Data("{}".utf8)) }
            return (200, Data("[]".utf8))
        }
        _ = try await rest().rpc("my_competitions")
        XCTAssertEqual(StubURLProtocol.requests.map { $0.url?.path },
                       ["/rest/v1/rpc/my_competitions", "/auth/v1/token", "/rest/v1/rpc/my_competitions"])
    }

    func testRefreshRefused_endsTheSession() async {
        keychain.save(FriendsStoredSession(access: "OLD", refresh: "R", expiresAt: Date().addingTimeInterval(10), userID: userID))
        StubURLProtocol.handler = { _ in (400, Data("{\"error\":\"invalid_grant\"}".utf8)) }
        let r = rest()
        do { _ = try await r.rpc("my_data"); XCTFail("expected notSignedIn") } catch {
            XCTAssertEqual(error as? FriendsError, .notSignedIn)
        }
        XCTAssertNil(keychain.load())
    }

    func testServerKey_mapsToFriendsError() async {
        keychain.save(FriendsStoredSession(access: "A", refresh: "R", expiresAt: Date().addingTimeInterval(3000), userID: userID))
        StubURLProtocol.handler = { _ in
            (400, Data("{\"code\":\"P0001\",\"message\":\"invite_expired\",\"details\":null,\"hint\":null}".utf8))
        }
        do { _ = try await rest().rpc("redeem_invite"); XCTFail("expected inviteExpired") } catch {
            XCTAssertEqual(error as? FriendsError, .inviteExpired)
        }
        XCTAssertEqual(SupabaseREST.mapError(status: 500, data: Data("{\"message\":\"boom\"}".utf8)), .server)
        XCTAssertEqual(SupabaseREST.mapError(status: 429, data: Data()), .rateLimited)
    }

    /// peek_invite / redeem_invite answer a refused code with 200 `{"error": key}` (a raise would roll back their
    /// rate-limit bump, so wrong guesses would never count). The backend throws it like a raised key.
    func testInviteRefusal_returnedAsErrorJSON_throwsTheKey() async {
        keychain.save(FriendsStoredSession(access: "A", refresh: "R", expiresAt: Date().addingTimeInterval(3000), userID: userID))
        StubURLProtocol.handler = { req in
            (200, Data((req.url?.path.hasSuffix("peek_invite") == true ? "{\"error\":\"invite_invalid\"}"
                                                                       : "{\"error\":\"invite_used\"}").utf8))
        }
        let backend = SupabaseFriendsBackend(rest: rest())
        do { _ = try await backend.peekInvite("ABCD2345"); XCTFail("expected inviteInvalid") } catch {
            XCTAssertEqual(error as? FriendsError, .inviteInvalid)
        }
        do { _ = try await backend.redeemInvite("ABCD2345"); XCTFail("expected inviteUsed") } catch {
            XCTAssertEqual(error as? FriendsError, .inviteUsed)
        }
        XCTAssertThrowsError(try FriendsJSON.throwIfError(Data("{\"error\":\"something_new\"}".utf8))) {
            XCTAssertEqual($0 as? FriendsError, .server, "an unknown key is a server error")
        }
        XCTAssertNoThrow(try FriendsJSON.throwIfError(Data("{\"display_name\":\"Sam\",\"expires_at\":\"2026-10-15T12:00:00+00:00\"}".utf8)))
    }

    func testNetworkFailure_mapsToNetwork() async {
        keychain.save(FriendsStoredSession(access: "A", refresh: "R", expiresAt: Date().addingTimeInterval(3000), userID: userID))
        StubURLProtocol.failure = URLError(.notConnectedToInternet)
        do { _ = try await rest().rpc("my_data"); XCTFail("expected network") } catch {
            XCTAssertEqual(error as? FriendsError, .network)
        }
    }

    func testEphemeralSession_noCacheNoCookies() {
        let s = SupabaseREST.makeSession()
        XCTAssertNil(s.configuration.urlCache)
        XCTAssertNil(s.configuration.httpCookieStorage)
        XCTAssertEqual(s.configuration.timeoutIntervalForRequest, 15)
    }

    func testKeychainRoundTrip_underATestServiceName() {
        let s = FriendsStoredSession(access: "a", refresh: "r", expiresAt: Date(timeIntervalSince1970: 1_800_000_000), userID: userID)
        XCTAssertTrue(keychain.save(s))
        XCTAssertEqual(keychain.load(), s)
        XCTAssertTrue(keychain.save(FriendsStoredSession(access: "b", refresh: "r", expiresAt: s.expiresAt, userID: userID)))
        XCTAssertEqual(keychain.load()?.access, "b", "save updates the one item")
        keychain.clear()
        XCTAssertNil(keychain.load())
        XCTAssertNil(FriendsKeychain(service: "com.patrickschmidt.baseline.friends.tests.other").load())
    }

    func testDelete_fallsBackToTheRPC_whenTheFunctionIsMissing() async throws {
        keychain.save(FriendsStoredSession(access: "A", refresh: "R", expiresAt: Date().addingTimeInterval(3000), userID: userID))
        StubURLProtocol.handler = { req in
            if req.url?.path == "/functions/v1/delete-account" { return (404, Data("{}".utf8)) }
            return (200, Data())
        }
        let backend = SupabaseFriendsBackend(rest: rest())
        let revoked = try await backend.deleteAccount(appleAuthorizationCode: "code")
        XCTAssertFalse(revoked)
        XCTAssertEqual(StubURLProtocol.requests.map { $0.url?.path },
                       ["/functions/v1/delete-account", "/rest/v1/rpc/delete_account"])
        XCTAssertNil(keychain.load(), "the local session is gone")
    }

    func testDelete_viaTheFunction_reportsRevoke() async throws {
        keychain.save(FriendsStoredSession(access: "A", refresh: "R", expiresAt: Date().addingTimeInterval(3000), userID: userID))
        StubURLProtocol.handler = { _ in (200, Data("{\"deleted\":true,\"revoked\":true}".utf8)) }
        let revoked = try await SupabaseFriendsBackend(rest: rest()).deleteAccount(appleAuthorizationCode: "code")
        XCTAssertTrue(revoked)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: StubURLProtocol.bodies.first ?? Data()) as? [String: String])
        XCTAssertEqual(body, ["authorizationCode": "code"])
    }

    func testOverviewDecoding() throws {
        let me = "11111111-2222-4333-8444-555555555555", alex = "aaaaaaaa-2222-4333-8444-555555555555"
        let json = """
        {"me":{"id":"\(me)","display_name":"Pat","step_goal":8000,"intensity_goal":150},
         "my_shares":[{"metric":"steps","audience":"friends"},{"metric":"hrv","audience":"friends"}],
         "hides":["\(alex)"],
         "friends":[{"id":"\(alex)","display_name":"Alex","step_goal":6000,"intensity_goal":150,"status":"accepted","requested_by_me":false}],
         "days":[{"user_id":"\(alex)","day":"2026-10-06","metric":"steps","value":7000,"source":"strap","capped":false},
                 {"user_id":"\(me)","day":"2026-10-06","metric":"steps","value":9000,"source":"phone","capped":false}],
         "trends":[{"user_id":"\(alex)","metric":"hrv","week_start":"2026-10-05","status":"ready","delta":8,"band":"within","clipped":false}]}
        """
        let o = try FriendsJSON.overview(Data(json.utf8))
        XCTAssertEqual(o.me.displayName, "Pat")
        XCTAssertEqual(o.myShares, [.steps: .friends, .hrv: .friends])
        XCTAssertEqual(o.myDays.map(\.value), [9_000])
        XCTAssertEqual(o.friends.first?.iHide, true)
        XCTAssertEqual(o.friends.first?.lastDay, "2026-10-06")
        XCTAssertEqual(o.friends.first?.trends.first?.delta, 8)
    }

    func testTimestampParsing() throws {
        let expected = ISO8601DateFormatter().date(from: "2026-10-15T12:00:00Z")!
        XCTAssertEqual(try FriendsJSON.date("2026-10-15T12:00:00+00:00"), expected)
        XCTAssertEqual(try FriendsJSON.date("2026-10-15T12:00:00.000000+00:00"), expected)
        XCTAssertEqual(try FriendsJSON.uuidScalar(Data("\"\(userID.uuidString.lowercased())\"".utf8)), userID)
    }
}

/// Answers every request from `handler` (or fails with `failure`) and records what was sent.
final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var _handler: ((URLRequest) -> (Int, Data))?
    private static var _failure: Error?
    private static var _requests: [URLRequest] = []
    private static var _bodies: [Data] = []

    static var handler: ((URLRequest) -> (Int, Data))? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); _handler = newValue; lock.unlock() }
    }
    static var failure: Error? {
        get { lock.lock(); defer { lock.unlock() }; return _failure }
        set { lock.lock(); _failure = newValue; lock.unlock() }
    }
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _requests }
    static var bodies: [Data] { lock.lock(); defer { lock.unlock() }; return _bodies }

    static func reset() {
        lock.lock()
        _handler = nil; _failure = nil; _requests = []; _bodies = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            stream.close()
        }
        Self.lock.lock()
        Self._requests.append(request)
        Self._bodies.append(body)
        let failure = Self._failure
        let handler = Self._handler
        Self.lock.unlock()
        if let failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let (status, data) = handler?(request) ?? (200, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
