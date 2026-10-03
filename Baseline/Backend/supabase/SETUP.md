# Friends server setup (Patrick's steps)

The Friends tab already works on demo friends before any of this is done: in the simulator, under sample data, and
behind the intro's "Preview with demo friends" button. These steps turn on the real, opt-in server. They are FRIENDS_SPEC.md
§11 word for word, plus the file names in this folder.

What lives here (none of it ships in the app; project.yml excludes `Backend`):

| File | What it is |
|---|---|
| `schema.sql` | Tables, RLS policies, RPCs, retention job. Run once in the SQL editor. Ends with a check query and a commented SELFTEST. |
| `functions/delete-account/index.ts` | Edge Function: revokes Sign in with Apple and deletes the account. |
| `tests/rls.sql`, `tests/rpc.sql`, `tests/scoring.sql` | pgTAP tests (`supabase test db`). |
| `Supabase.example.plist` | The app config template (placeholders only). |
| `config.toml` | Minimal Supabase CLI config, `project_id = "baseline-friends"`. |

## Steps

1. **Check the developer account type** for team 25RC553RGP (developer.apple.com › Membership). Guideline
   5.1.1(ix) expects an organisation for sensitive health data. If the account is Individual, either ship Release
   without `Supabase.plist` (the tab offers the demo preview only) or accept the risk knowingly.
2. **Create the Supabase project.** supabase.com → New project "baseline-friends", region **Central EU
   (Frankfurt)**, a strong DB password in your password manager. **Pro plan** is recommended, because free projects
   pause after about 7 idle days. Sign the DPA (Organization › Legal documents).
3. **Run the schema.** Database › Extensions: enable **pg_cron**. SQL editor: paste and run
   `Baseline/Backend/supabase/schema.sql`. The final query must print `policies 12, anon_table_grants 0,
   authenticated_write_grants 0, api_policy_helpers 0`. Re-running the file on an existing project is how schema
   fixes ship (it moves the policy helpers out of the API schema and refreshes the blocked words). Optionally run the commented SELFTEST block (select from `do $$` to the last `$$;`
   after removing the leading `-- `); it prints "SELFTEST passed".
4. **Turn on the Apple provider.** Authentication › Sign In / Providers:
   - Disable Email, Phone and Anonymous.
   - Enable **Apple** with Client IDs = `com.patrickschmidt.baseline`; no secret key is needed for native sign-in.
   - Turn on "Allow users without an email" if offered. If it isn't, tell a builder to switch on the D20 fallback
     (`AppleSignIn.requestedScopes = [.email]`, plus Email Address in the privacy manifest and the App Store label).
   - Authentication › Sessions: JWT expiry 3600, refresh-token rotation on.
5. **Register the capability.** Apple Developer › Identifiers › `com.patrickschmidt.baseline`: enable **Sign in with
   Apple** (Enable as primary App ID) and save. Xcode's automatic signing then regenerates the profile.
   (Until this is done, device builds fail on the new `com.apple.developer.applesignin` entitlement; simulator
   builds and UI tests are unaffected.)
6. **Create a Sign in with Apple key.** Apple Developer › Keys › "+": name it "Baseline Sign in with Apple", tick
   Sign in with Apple, configure it for `com.patrickschmidt.baseline`, and register. Download the `.p8` **once**
   and note the Key ID.
   - Create a **new** key; never reuse or open Sayner's.
   - Keep the `.p8` out of every repo.
7. **Deploy the delete-account function.** `brew install supabase/tap/supabase`, then from
   `Baseline/Backend`:
   ```sh
   supabase login
   supabase link --project-ref <ref>
   supabase secrets set APPLE_TEAM_ID=25RC553RGP APPLE_KEY_ID=<key id> APPLE_CLIENT_ID=com.patrickschmidt.baseline APPLE_PRIVATE_KEY="$(cat ~/path/AuthKey_<id>.p8)"
   supabase functions deploy delete-account
   ```
   The service-role key is injected automatically; never copy it anywhere.
8. **Add the app config.** Copy `Baseline/Backend/supabase/Supabase.example.plist` to
   `Baseline/Resources/Supabase.plist`. Paste the Project URL (`https://<ref>.supabase.co`) and the
   anon/publishable key (Settings › API). **Never** use the service_role or secret key; the app refuses them.
   `git status` must show the file as ignored (`Baseline/Resources/.gitignore` lists it).
9. **Build.** Run `xcodegen generate` and build to a device. Smoke test with a second Apple ID:
   - code → peek → redeem → accept
   - share Steps → see each other
   - create a steps competition
   - turn Steps off → the friend's row disappears
   - delete one account → the dashboard shows zero rows for that id
10. **Optional:** Docker + the Supabase CLI run the RLS, RPC and scoring tests locally. The CLI applies migrations,
    not `schema.sql`, so copy it in first (the copy is a local scratch file; delete it afterwards):
    ```sh
    cd Baseline/Backend
    mkdir -p supabase/migrations && cp supabase/schema.sql supabase/migrations/20261002000000_friends.sql
    supabase start && supabase test db
    rm -r supabase/migrations
    ```
11. **App Store Connect.**
    - Update App Privacy exactly as in `Store/PrivacyNutrition.md`.
    - Re-answer the age-rating questionnaire (display names as user-generated content, with report and block).
    - Paste the new `ReviewNotes.md`.
    - Publish the updated privacy policy.
    - Check the `reports` table weekly; to act on a report, block or delete the profile from the dashboard.
12. **Keep the DPIA and record of processing** (outline in PRIVACY.md).

## How the app picks a backend

`FriendsBackendFactory.choose(...)` (Baseline/Friends/FriendsBackendFactory.swift), in order:

1. DEBUG `--ui-testing`, `--friends-demo`, `--friends-state signedOut|setup|ready` or `--demo-seed` → demo.
2. Sample data on → demo (even with a config: synthetic numbers never reach the server).
3. A valid `Supabase.plist` → live.
4. "Preview with demo friends" tapped this session → demo.
5. Otherwise → no backend; the intro offers the preview.

Demo invite codes (all from the invite alphabet): `CASEY234` adds Casey as a pending request, `XPRDCDE2` is expired,
`USEDCDE2` is used, and the code the demo's Invite sheet shows is your own (`invite_self`).
