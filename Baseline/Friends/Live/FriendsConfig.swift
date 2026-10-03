import Foundation

/// The person's own Supabase project, read from `Supabase.plist` in the app bundle (git-ignored; copied from
/// Baseline/Backend/supabase/Supabase.example.plist by the owner, SETUP.md step 8). A missing or unsafe file means no
/// live backend: Friends then offers only the demo preview. Never crashes on a bad file.
struct FriendsConfig: Equatable, Sendable {
    let url: URL
    let anonKey: String

    static let resourceName = "Supabase"
    static let urlKey = "SUPABASE_URL"
    static let keyKey = "SUPABASE_ANON_KEY"
    /// Text the example plist ships with; a file still carrying one is treated as missing.
    static let placeholders = ["YOUR-PROJECT", "PASTE_"]

    /// nil when the file is missing, still a placeholder, not https, or holds a key the app must never carry
    /// (`sb_secret_…`, or a JWT whose role is `service_role`, or anything that is neither a publishable key nor an
    /// anon JWT).
    static func load(bundle: Bundle = .main) -> FriendsConfig? {
        guard let path = bundle.path(forResource: resourceName, ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else { return nil }
        return make(url: dict[urlKey] as? String, key: dict[keyKey] as? String)
    }

    static func make(url rawURL: String?, key rawKey: String?) -> FriendsConfig? {
        guard let rawURL, let rawKey else { return nil }
        let urlString = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty, !key.isEmpty else { return nil }
        if placeholders.contains(where: { urlString.contains($0) || key.contains($0) }) { return nil }
        guard let url = URL(string: urlString), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else { return nil }
        guard isClientSafe(key: key) else { return nil }
        return FriendsConfig(url: url, anonKey: key)
    }

    /// Only a publishable key (`sb_publishable_…`) or a legacy anon JWT (`role: anon`) is accepted.
    static func isClientSafe(key: String) -> Bool {
        if key.hasPrefix("sb_secret_") { return false }
        if key.hasPrefix("sb_publishable_") { return true }
        guard let role = jwtRole(key) else { return false }
        return role == "anon"
    }

    /// The `role` claim of a JWT, or nil when the string is not a decodable JWT.
    static func jwtRole(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["role"] as? String
    }
}
