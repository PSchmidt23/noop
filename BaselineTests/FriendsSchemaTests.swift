import XCTest
@testable import Baseline

/// A smoke test over Baseline/Backend/supabase/schema.sql, read from the source tree: every table has RLS on, there are
/// exactly 12 SELECT-only policies, every RPC is granted to `authenticated` (never `anon`), the policy helpers are not
/// RPCs, every error key the SQL raises or returns is a `FriendsError`, and the blocked-word seed matches
/// `DisplayName.blockedSubstrings` / `blockedWholeWords`. It cannot run the SQL (that
/// is tests/*.sql under `supabase test db`), but it catches the drift a Swift-only change would otherwise hide.
final class FriendsSchemaTests: XCTestCase {

    private func schema() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Baseline/Backend/supabase/schema.sql")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("schema.sql not readable from this test host (\(url.path))")
        }
        // Drop line comments, so the commented SELFTEST and prose never count.
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let r = line.range(of: "--") else { return line }
                return line[..<r.lowerBound]
            }
            .joined(separator: "\n")
    }

    private func matches(_ pattern: String, in text: String) -> [[String]] {
        let re = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    func testEveryTableHasRowLevelSecurity() throws {
        let sql = try schema()
        let tables = Set(matches(#"create table if not exists public\.(\w+)"#, in: sql).map { $0[1] })
        let rls = Set(matches(#"alter table public\.(\w+)\s+enable row level security"#, in: sql).map { $0[1] })
        XCTAssertEqual(tables.count, 15)
        XCTAssertEqual(tables, rls, "tables without RLS: \(tables.subtracting(rls))")
    }

    func testTwelveSelectOnlyPolicies() throws {
        let sql = try schema()
        let policies = matches(#"create policy (\w+)\s+on public\.(\w+)\s+for (\w+)\s+to (\w+)"#, in: sql)
        XCTAssertEqual(policies.count, 12)
        XCTAssertTrue(policies.allSatisfy { $0[3].lowercased() == "select" }, "write policies exist")
        XCTAssertTrue(policies.allSatisfy { $0[4].lowercased() == "authenticated" })
        let daily = policies.filter { ["daily_values", "trend_values"].contains($0[2]) }
        XCTAssertEqual(daily.count, 2)
        XCTAssertTrue(sql.contains("using (private.can_see(user_id, metric))"), "one privacy rule for health rows")
        // A block hides the other person's competition rows as well (the RPCs already filter blocks).
        for table in ["competition_members", "competition_results"] {
            guard let r = sql.range(of: #"on public\.\#(table)\s+for select to authenticated\s+using \(([^;]*)\);"#,
                                    options: .regularExpression) else { XCTFail(table); continue }
            XCTAssertTrue(sql[r].contains("private.is_blocked_between(user_id)"), "\(table) ignores blocks")
            // Final results, like competition_standings, go only to people who took part, never to someone invited.
            if table == "competition_results" {
                XCTAssertTrue(sql[r].contains("m.state in ('joined','left')"), "an invited member reads final results")
            }
        }
    }

    /// The five policy helpers live in `private`, which PostgREST does not expose, so a blocked person cannot call
    /// /rest/v1/rpc/is_blocked_between to confirm a block or probe can_see for someone's sharing.
    func testPolicyHelpersAreNotRPCs() throws {
        let sql = try schema()
        let helpers = ["is_blocked_between", "are_friends", "can_see", "knows", "is_competition_member"]
        for h in helpers {
            XCTAssertTrue(sql.contains("create or replace function private.\(h)("), "\(h) is not in private")
            XCTAssertFalse(sql.contains("create or replace function public.\(h)("), "\(h) is still an RPC")
            XCTAssertTrue(matches(#"grant execute on function private\.\#(h)\([^)]*\)\s+to authenticated"#, in: sql).count == 1,
                          "\(h) is not executable inside policies")
            XCTAssertTrue(sql.contains("drop function if exists public.\(h)("), "an older project keeps public.\(h)")
            XCTAssertEqual(sql.components(separatedBy: "public.\(h)(").count - 1, 1,
                           "public.\(h) is referenced somewhere other than its drop")
        }
    }

    func testEveryRPCIsGrantedToAuthenticated_andNothingToAnon() throws {
        let sql = try schema()
        let functions = Set(matches(#"create or replace function public\.(\w+)\("#, in: sql).map { $0[1] })
        let granted = Set(matches(#"grant execute on function public\.(\w+)\([^)]*\)\s+to authenticated"#, in: sql).map { $0[1] })
        XCTAssertEqual(functions, granted, "ungranted: \(functions.subtracting(granted)); stray: \(granted.subtracting(functions))")
        XCTAssertTrue(matches(#"grant [^;]* to anon\b"#, in: sql).isEmpty, "anon is granted something")
        XCTAssertTrue(matches(#"grant (insert|update|delete|all)\b"#, in: sql).isEmpty, "a write grant exists")
        let lockdowns = matches(#"revoke all on all tables\s+in schema public from anon, authenticated"#, in: sql)
        XCTAssertGreaterThanOrEqual(lockdowns.count, 2, "default grants are revoked at the top AND the end")
    }

    func testRPCsCheckTheProfileAndTheRate() throws {
        let sql = try schema()
        // Every public function is an RPC (the policy helpers live in private).
        let rpcs = matches(#"create or replace function public\.(\w+)\((?s:.*?)\$\$(?s:(.*?))\$\$;"#, in: sql)
        XCTAssertEqual(rpcs.count, 22)
        for rpc in rpcs where rpc[1] != "complete_profile" && rpc[1] != "delete_account" {
            XCTAssertTrue(rpc[0].contains("private.require_profile()"), "\(rpc[1]) skips require_profile")
            XCTAssertTrue(rpc[0].contains("private.bump_rate("), "\(rpc[1]) has no rate limit")
        }
        for rpc in rpcs {
            XCTAssertTrue(rpc[0].contains("set search_path = public"), "\(rpc[1]) has no fixed search_path")
        }
    }

    /// Keys reach the client two ways: raised (PostgREST's `message`) or, from peek_invite and redeem_invite, returned
    /// as {"error": key} so their rate limit counts refused codes. Both must map onto `FriendsError`.
    func testEveryRaisedOrReturnedKeyIsAFriendsError() throws {
        let sql = try schema()
        let raised = Set(matches(#"raise exception '([a-z_]+)'"#, in: sql).map { $0[1] })
        let returned = Set(matches(#"jsonb_build_object\('error', '([a-z_]+)'\)"#, in: sql).map { $0[1] })
        XCTAssertFalse(raised.isEmpty)
        XCTAssertTrue(returned.isSuperset(of: ["invite_invalid", "invite_self", "invite_used", "invite_expired",
                                               "blocked", "already_friends", "friend_limit"]))
        let keys = raised.union(returned)
        for key in keys { XCTAssertNotNil(FriendsError(rawValue: key), "SQL sends \(key), which Swift can't map") }
        XCTAssertEqual(keys, Set(FriendsError.serverKeys.map(\.rawValue)), "every Swift key is sent somewhere")
    }

    /// A refused invite code must not raise: a raise rolls back the call's bump_rate, so wrong guesses would never
    /// count toward the 30 (peek) and 10 (redeem) an hour.
    func testInviteRPCsReturnRefusalsSoTheRateLimitCountsThem() throws {
        let sql = try schema()
        for rpc in ["peek_invite", "redeem_invite"] {
            guard let r = sql.range(of: #"create or replace function public\.\#(rpc)\((?s:.*?)end \$\$;"#,
                                    options: .regularExpression) else { XCTFail(rpc); continue }
            let body = String(sql[r])
            XCTAssertTrue(body.contains("private.bump_rate("), rpc)
            XCTAssertFalse(body.contains("raise exception"), "\(rpc) raises after its bump_rate")
        }
    }

    func testBlockedWordsMatchTheSwiftLists() throws {
        let sql = try schema()
        guard let seed = sql.range(of: "with seed(word, whole_word) as (values"),
              let end = sql.range(of: "), retired as (", range: seed.upperBound..<sql.endIndex) else {
            return XCTFail("no blocked_words seed")
        }
        let rows = matches(#"\('([^']+)',\s*(true|false)\)"#, in: String(sql[seed.upperBound..<end.lowerBound]))
        XCTAssertEqual(rows.filter { $0[2] == "false" }.map { $0[1] }, DisplayName.blockedSubstrings)
        XCTAssertEqual(rows.filter { $0[2] == "true" }.map { $0[1] }, DisplayName.blockedWholeWords)
        XCTAssertTrue(sql.contains("regexp_replace(v_lower, '[^a-z0-9]+', ' ', 'g')"),
                      "valid_name reads words the way DisplayName.words does")
    }

    func testMetricVocabularyMatchesSwift() throws {
        let sql = try schema()
        XCTAssertTrue(sql.contains("metric in ('steps','intensity','active','sleep_goal','bedtime','hrv','rhr','readiness')"))
        XCTAssertEqual(FriendsMetric.allCases.map(\.rawValue).joined(separator: ","),
                       "steps,intensity,active,sleep_goal,bedtime,hrv,rhr,readiness")
        XCTAssertTrue(sql.contains("code ~ '^[A-HJ-NP-Z2-9]{8}$'"))
        XCTAssertTrue(sql.contains("'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'"))
        XCTAssertEqual(FriendInviteCode.charset, "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    }
}
