import Foundation

/// A dependency-free client for the five Supabase endpoints Friends uses (FRIENDS_SPEC.md D1, §5.4):
/// - `POST /auth/v1/token?grant_type=id_token` (Apple identity token + the RAW nonce)
/// - `POST /auth/v1/token?grant_type=refresh_token`
/// - `POST /auth/v1/logout`
/// - `POST /rest/v1/rpc/{name}` (every write and most reads), plus one `GET /rest/v1/profiles` for the own profile
/// - `POST /functions/v1/delete-account`
///
/// Ephemeral session: no URL cache, no cookies, 15 s timeout. The access token is refreshed proactively when it has
/// under 60 s left (one refresh at a time), and a 401 is retried once after a forced refresh. PostgREST errors carry
/// the server's stable key in `message`, which maps straight onto `FriendsError`.
actor SupabaseREST {
    let config: FriendsConfig
    let session: URLSession
    let keychain: FriendsKeychain
    private let now: @Sendable () -> Date
    private var stored: FriendsStoredSession?
    private var restored = false
    private var refreshTask: Task<FriendsStoredSession, Error>?

    static let timeout: TimeInterval = 15
    static let refreshMargin: TimeInterval = 60

    init(config: FriendsConfig, keychain: FriendsKeychain = FriendsKeychain(), session: URLSession? = nil,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config
        self.keychain = keychain
        self.session = session ?? SupabaseREST.makeSession()
        self.now = now
    }

    /// Ephemeral, cache-free, cookie-free. `protocolClasses` lets tests stub the network.
    static func makeSession(protocolClasses: [AnyClass]? = nil) -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = timeout
        c.timeoutIntervalForResource = timeout * 2
        if let protocolClasses { c.protocolClasses = protocolClasses + (c.protocolClasses ?? []) }
        return URLSession(configuration: c)
    }

    // MARK: - Session

    private func restoreIfNeeded() {
        guard !restored else { return }
        restored = true
        stored = keychain.load()
    }

    var currentSession: FriendsStoredSession? {
        restoreIfNeeded()
        return stored
    }

    var userID: UUID? { currentSession?.userID }

    /// Exchanges an Apple identity token for a Supabase session. `nonce` is the RAW nonce (Apple signed its SHA-256).
    @discardableResult
    func signInWithIdToken(idToken: String, nonce: String) async throws -> FriendsStoredSession {
        let body = try JSONSerialization.data(withJSONObject: ["provider": "apple", "id_token": idToken, "nonce": nonce])
        let data = try await sendAuth(path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "id_token")], body: body)
        let s = try decodeSession(data)
        store(s)
        return s
    }

    /// A fresh session from the refresh token. Single flight: concurrent callers share one request.
    @discardableResult
    func refresh() async throws -> FriendsStoredSession {
        if let refreshTask { return try await refreshTask.value }
        guard let current = currentSession else { throw FriendsError.notSignedIn }
        let task = Task { () throws -> FriendsStoredSession in
            let body = try JSONSerialization.data(withJSONObject: ["refresh_token": current.refresh])
            var req = self.request(path: "auth/v1/token", method: "POST",
                                   query: [URLQueryItem(name: "grant_type", value: "refresh_token")])
            req.setValue("Bearer \(self.config.anonKey)", forHTTPHeaderField: "Authorization")
            req.httpBody = body
            let (data, response) = try await self.perform(req)
            // 4xx: the refresh token is gone (revoked, rotated away, user deleted), so the session is over.
            if (400..<500).contains(response.statusCode) { throw FriendsError.notSignedIn }
            guard (200..<300).contains(response.statusCode) else { throw Self.mapError(status: response.statusCode, data: data) }
            return try self.decodeSession(data)
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let s = try await task.value
            store(s)
            return s
        } catch FriendsError.notSignedIn {
            clearSession()
            throw FriendsError.notSignedIn
        }
    }

    /// A valid access token, refreshed first when under a minute is left.
    func accessToken() async throws -> String {
        guard let s = currentSession else { throw FriendsError.notSignedIn }
        if s.expiresAt.timeIntervalSince(now()) < Self.refreshMargin {
            return try await refresh().access
        }
        return s.access
    }

    /// Best effort: the server revokes the refresh token; the local session is cleared either way.
    func logout() async {
        if let token = currentSession?.access {
            var req = request(path: "auth/v1/logout", method: "POST")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.httpBody = Data("{}".utf8)
            _ = try? await session.data(for: req)
        }
        clearSession()
    }

    func clearSession() {
        stored = nil
        restored = true
        keychain.clear()
    }

    private func store(_ s: FriendsStoredSession) {
        stored = s
        restored = true
        keychain.save(s)
    }

    // MARK: - Calls

    /// `POST /rest/v1/rpc/{name}` with a JSON object body. Returns the raw response body ("" for `void`).
    func rpc(_ name: String, body: Data = Data("{}".utf8)) async throws -> Data {
        try await authorized { token in
            var req = self.request(path: "rest/v1/rpc/\(name)", method: "POST")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.httpBody = body
            return req
        }
    }

    /// `GET /rest/v1/{table}?{query}` (used only for the caller's own profile row).
    func select(_ table: String, query: [URLQueryItem]) async throws -> Data {
        try await authorized { token in
            var req = self.request(path: "rest/v1/\(table)", method: "GET", query: query)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return req
        }
    }

    /// `POST /functions/v1/{name}`: returns the status and body without mapping errors (the caller falls back).
    func function(_ name: String, body: Data) async throws -> (status: Int, data: Data) {
        let token = try await accessToken()
        var req = request(path: "functions/v1/\(name)", method: "POST")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        let (data, response) = try await perform(req)
        return (response.statusCode, data)
    }

    /// Runs a request with a valid token; a 401 forces one refresh and one retry.
    private func authorized(_ build: @Sendable (String) -> URLRequest) async throws -> Data {
        var token = try await accessToken()
        var (data, response) = try await perform(build(token))
        if response.statusCode == 401 {
            token = try await refresh().access
            (data, response) = try await perform(build(token))
            if response.statusCode == 401 { clearSession(); throw FriendsError.notSignedIn }
        }
        guard (200..<300).contains(response.statusCode) else { throw Self.mapError(status: response.statusCode, data: data) }
        return data
    }

    private func sendAuth(path: String, query: [URLQueryItem], body: Data) async throws -> Data {
        var req = request(path: path, method: "POST", query: query)
        req.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        let (data, response) = try await perform(req)
        guard (200..<300).contains(response.statusCode) else { throw Self.mapError(status: response.statusCode, data: data) }
        return data
    }

    private func perform(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw FriendsError.server }
            return (data, http)
        } catch let e as FriendsError {
            throw e
        } catch {
            throw FriendsError.network
        }
    }

    nonisolated func request(path: String, method: String, query: [URLQueryItem] = []) -> URLRequest {
        var comps = URLComponents(url: config.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        req.httpMethod = method
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    // MARK: - Decoding

    private struct TokenResponse: Decodable {
        struct User: Decodable { let id: UUID }
        let access_token: String
        let refresh_token: String
        let expires_in: Double?
        let expires_at: Double?
        let user: User
    }

    nonisolated func decodeSession(_ data: Data) throws -> FriendsStoredSession {
        guard let t = try? JSONDecoder().decode(TokenResponse.self, from: data) else { throw FriendsError.server }
        let expiry: Date
        if let at = t.expires_at { expiry = Date(timeIntervalSince1970: at) }
        else { expiry = now().addingTimeInterval(t.expires_in ?? 3600) }
        return FriendsStoredSession(access: t.access_token, refresh: t.refresh_token, expiresAt: expiry, userID: t.user.id)
    }

    /// PostgREST `{code, message, details, hint}` → `FriendsError(rawValue: message)`; GoTrue `{error, msg,
    /// error_description}` → `.notSignedIn` for 400/401/403 on auth, else `.server`.
    static func mapError(status: Int, data: Data) -> FriendsError {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        for key in ["message", "msg", "error_code", "error"] {
            if let s = obj?[key] as? String, let e = FriendsError(rawValue: s.trimmingCharacters(in: .whitespaces)) {
                return e
            }
        }
        if status == 401 || status == 403 { return .notSignedIn }
        if status == 429 { return .rateLimited }
        return .server
    }
}
