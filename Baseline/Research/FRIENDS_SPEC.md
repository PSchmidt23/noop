# Friends: final build spec (v1)

*Synthesised 2 October 2026 from designer #1 (privacy first), with grafts the judges picked from designers #2 and #3.
This file settles every open question. Builders read this instead of the three proposals. Background and citations
are in SOCIAL_FEATURES.md; the activity inputs are in ACTIVITY_METRICS.md and ACTIVITY_AUDIT.md.*

## 0. The answer to Patrick, and the rule everything follows

Yes, you're right. One person's HRV or resting HR tells you nothing when you set it next to someone else's.
Short-term HRV varies between healthy people by orders of magnitude (Nunan 2010), and ranking even the *change*
rewards regression to the mean and slacking off on purpose. So:

- **Behaviour competes head-to-head:** Steps, Intensity minutes, Active days, Nights at your own sleep goal, and
  On-time bedtimes. Scoring defaults to **% of each person's own goal**.
- **Physiology** (HRV, Resting HR, Readiness) is shown only as each person's change against their own baseline,
  rounded and clipped ("HRV +8 % vs own baseline"). It is listed alphabetically, never ranked, never in a
  competition, and never in a notification.
- **Never shared at all:** Calories and Stress (low accuracy), raw HR/HRV/RHR/readiness, samples, sleep hours,
  clock times, journal, location, skin temperature, SpO2, breathing rate, and illness signals.
- Friends is an **opt-in fourth tab**. Home, Trends and Sleep never need an account. Release builds without a
  server config still offer a session-only "Preview with demo friends".

## 1. Resolved decisions (one line each)

| # | Question | Decision |
|---|---|---|
| D1 | supabase-swift or a REST client | A **dependency-free URLSession REST client**. The package would need NOOP's shared `packages:` block and Package.resolved, plus about 6 transitive exact pins, all for 5 endpoints. |
| D2 | Where writes happen | **RPC only.** Clients get no INSERT/UPDATE/DELETE grant on any table. Supabase's default grants are revoked both at the top and at the end of schema.sql. |
| D3 | The visibility rule | A single `can_see(owner, metric)` security-definer function is the only SELECT policy on both health tables. |
| D4 | Sharing levels | Each metric is **Off / Only in competitions / Friends**, Off by default. Physiology is Off / Friends only. |
| D5 | Sleep and bedtime upload form | 0/1 per night ("reached own sleep goal", "bedtime within ±30 min of own target"). Never minutes or clock times. |
| D6 | Physiology history | Graft (j): **one row per local ISO week**, at most the current week plus 4 previous, clipped and rounded. The friend detail draws 4–5 neutral points around a zero line labelled "own baseline". No daily history. |
| D7 | Friending | A two-step flow. Server-generated code (8 chars, no 0/O/1/I/l, single use, 7 days) or the link `baseline://friends/join/CODE`. `peek_invite` shows "Connect with Sam?", redeeming creates a PENDING request, and the inviter accepts. |
| D8 | Competition scope v1 | Steps: `goal_percent`, `total`, `days_at_goal`. Intensity: `goal_percent`, `total`. Active days, Nights at sleep goal, On-time bedtimes: `total` (a count of days). **Deferred to v1.1:** `improvement` and `together` (group goal). Physiology competitions are never built. |
| D9 | Leaderboard computation | Not done on the server. `friends_overview` returns the visible rows and the pure Swift `FriendsBoard` ranks them. The server scores **competitions** only. |
| D10 | Leaderboard motivation | Graft (h): the headline names only the person directly above you ("You're 2nd of 5 · 6 % behind Alex", the gap in the rows' own unit). Graft (g): a per-viewer **Competitive view** switch, local only and on by default; off means alphabetical with no places and no headline. |
| D11 | Rematch | Graft (i): a "Rematch" button on a finished competition calls `create_competition` with the same metric, mode, length and still-friend members, starting next Monday. No recurrence. |
| D12 | Backend choice | Graft: a pure `FriendsBackendFactory.choose(...)`. Sample data, `--demo-seed`, `--ui-testing` and `--friends-demo*` always force the demo backend, even when a config exists. |
| D13 | Config safety | Graft: `FriendsConfig` rejects a key whose JWT `role` is `service_role` and any `sb_secret_…` key. release-check does the same check on the bundled plist. |
| D14 | Demo error paths | Graft: fixed demo codes `DEMO2345` (adds Casey, pending), `XPRDCDE2` (`invite_expired`), `USEDCDE2` (`invite_used`), and your own code (`invite_self`). Plus the launch argument `--friends-state signedOut\|setup\|ready`. |
| D15 | freeze time | A plain `freeze_at timestamptz` column, set only by `create_competition` to `(end_day + 3) 12:00 UTC`, which is 48 h after the last day ends in UTC−12. It is not a generated column, which avoids immutability errors. Finalising happens lazily inside `competition_standings` under a `for update` lock, and pg_cron sweeps as well. |
| D16 | Sleep goal | A new `baseline.sleepGoalMinutes` setting: default 450 (7 h 30), range 300–600 in steps of 15, with a stepper in Settings › Profile beside the sleep window. A night counts when **asleep** minutes ≥ the goal. |
| D17 | Bedtime | 1 when `BaselineReadouts.clockDistance(bed, SleepWindow.stored().bedMinutes) ≤ 30`. Bed time only; wake time is not counted. |
| D18 | "Hide my data from X" | Stored in its own table `friend_hides(owner, viewer)`, which only the owner can read, so the friend cannot see that you've hidden from them. Mute stays local. |
| D19 | Display name | 2–24 characters after NFKC normalisation, trimming and whitespace collapsing. Rejected: control characters, `< > @ / \ :`, "http", "www.", and words on the blocked list. The rule is a negative list (no `[[:alnum:]]`), so "Ana-María" passes on any collation. |
| D20 | Email and name scopes | `requestedScopes = []`. The documented fallback, if Supabase refuses Apple users without an email, is `[.email]`, which adds Email Address to the privacy label. |
| D21 | Notifications | None in v1: no push and no local Friends notifications. The tab badge shows incoming requests plus competition invitations. |
| D22 | Release without config | Graft: the intro shows "Preview with demo friends" for the session only, so App Review can try the tab without signing in. |
| D23 | Folder layout | Client code goes in `Baseline/Friends/…`, UI in `Baseline/Screens/Friends/`, and SQL, the Edge Function, tests and the setup doc in `Baseline/Backend/supabase/`, which project.yml excludes. |
| D24 | Cut order if the pass runs long | 1) `my_data` export screen (keep the RPC), 2) the trend history chart (keep the current pill), 3) Rematch, 4) the `--friends-state` variants. **Never cut:** consent, withdrawal deleting the rows, delete account, report, block, hide, or the demo backend. |

## 2. File layout

```
Baseline/
  Backend/supabase/                     (excluded from the bundle: project.yml exclude "Backend")
    config.toml                         minimal `supabase init` output, project_id = "baseline-friends"
    schema.sql                          run once in the SQL editor; idempotent where cheap; ends with checks + commented selftest
    functions/delete-account/index.ts   Deno Edge Function (Apple revoke + admin delete)
    tests/rls.sql  tests/rpc.sql  tests/scoring.sql   pgTAP, `supabase test db`
    Supabase.example.plist              placeholders (committed)
    SETUP.md                            the owner steps of §11, word for word
  Resources/
    Supabase.plist                      the real config, git-ignored, bundled when present
    .gitignore                          contains exactly: Supabase.plist   (project.yml exclude "Resources/.gitignore")
  Friends/
    FriendsModels.swift                 contract: Foundation only (Builder B, day 0)
    FriendsBackend.swift                contract: protocol + FriendsBackendKind (Builder B, day 0)
    FriendsScoring.swift                pure competition scoring (mirrors SQL)
    FriendsBoard.swift                  pure leaderboard + headline + friend week
    FriendsUploadBuilder.swift          pure: local readouts → [DailyShare], [TrendShare]
    FriendsUploadInputs.swift           @MainActor loader that reads BaselineReadouts/BaselineDays into the builder's inputs
    FriendsStore.swift                  @MainActor ObservableObject: phase, data, upload scheduler
    FriendsBackendFactory.swift         pure choose(...)
    AppleSignIn.swift                   nonce + SHA-256 + reauthorizeForDeletion()
    Live/FriendsConfig.swift
    Live/SupabaseREST.swift
    Live/FriendsKeychain.swift
    Live/SupabaseFriendsBackend.swift
    Demo/LocalDemoFriendsBackend.swift
    Demo/LocalDemoFriendsSeed.swift
  Screens/Friends/
    FriendsScreen.swift  FriendsIntroView.swift  FriendsSetupSheet.swift  FriendsConsentView.swift
    FriendsRequestsCard.swift  LeaderboardCard.swift  FriendWeekCard.swift  FriendDetailScreen.swift
    InviteSheet.swift  EnterCodeSheet.swift
    CompeteSection.swift  CompetitionCard.swift  CompetitionDetailScreen.swift  CreateCompetitionSheet.swift
  Screens/Settings/
    SettingsFriends.swift               SettingsFriendsCard + FriendsSharingScreen
    SharedDataScreen.swift              "See what's on the server"
    SettingsSleepWindow.swift           the D16 "Sleep goal" stepper, a row of the Profile section's Sleep window card
BaselineTests/   FriendsScoringTests, FriendsBoardTests, FriendsUploadBuilderTests, FriendsStoreTests,
                 FriendsBackendFactoryTests, FriendsConfigTests, FriendsModelsTests, SupabaseRESTTests,
                 LocalDemoFriendsBackendTests, + additions to BaselineRootLaunchTests and WidgetSnapshotTests
BaselineUITests/ ScreenshotTests (+ Friends tests)
```

`project.yml`, Baseline blocks only:
- Source excludes: add `"Backend"` and `"Resources/.gitignore"`.
- Entitlements properties: add `com.apple.developer.applesignin: [Default]`.
- Info.plist comment: replace "Baseline makes no network connections" with "Baseline connects only to the person's
  own Supabase project over HTTPS, and only when Friends is used; ITSAppUsesNonExemptEncryption stays false (OS
  TLS, CryptoKit SHA-256)."
- No new usage strings.

No NOOP file, the root `.gitignore`, the shared `packages:` block or Package.resolved is touched.

## 3. Data model: `Baseline/Backend/supabase/schema.sql`

Day keys are each person's **local** calendar date (Baseline's "yyyy-MM-dd"), stored as `date`. The server never
converts time zones.

### 3.0 Header and lockdown

```sql
-- Run in the Supabase SQL editor (project region: Central EU / Frankfurt) after enabling pg_cron.
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_cron;

revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
```

### 3.1 Tables

```sql
create table public.profiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  display_name     text not null,
  step_goal        int  not null default 8000 check (step_goal between 3000 and 30000),
  intensity_goal   int  not null default 150  check (intensity_goal between 60 and 600),   -- weekly minutes
  age_confirmed_at timestamptz not null,                                                   -- 16+ self-declaration
  created_at       timestamptz not null default now(),
  last_seen_at     timestamptz not null default now(),
  constraint display_name_shape check (
        char_length(display_name) between 2 and 24
    and display_name = btrim(display_name)
    and display_name !~ '[[:cntrl:]<>@/\\:]'
    and display_name !~* '(https?|www\.)')
);
-- No trigger on auth.users: the row is created by complete_profile(), because the name is typed in the app.

create table public.share_settings (
  user_id         uuid not null references public.profiles(id) on delete cascade,
  metric          text not null check (metric in ('steps','intensity','active','sleep_goal','bedtime','hrv','rhr','readiness')),
  audience        text not null check (audience in ('competitions','friends')),
  consent_version int  not null check (consent_version >= 1),
  granted_at      timestamptz not null default now(),
  primary key (user_id, metric),
  check (metric not in ('hrv','rhr','readiness') or audience = 'friends')
);  -- no row = Off. The row is the live consent record.

create table public.consent_log (
  id        bigserial primary key,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  metric    text not null,
  audience  text null,           -- null = withdrawn
  version   int  not null,
  at        timestamptz not null default now()
);

create table public.daily_values (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  day        date not null,
  metric     text not null check (metric in ('steps','intensity','active','sleep_goal','bedtime')),
  value      int  not null,
  source     text null check (source in ('strap','phone')),
  capped     boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, metric, day),
  check (case metric when 'steps'     then value between 0 and 60000
                     when 'intensity' then value between 0 and 300
                     else value in (0,1) end),
  check ((metric = 'steps') = (source is not null))
);
create index daily_values_day on public.daily_values(day);

create table public.trend_values (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  metric     text not null check (metric in ('hrv','rhr','readiness')),
  week_start date not null check (extract(isodow from week_start) = 1),   -- the owner's local Monday
  status     text not null check (status in ('calibrating','ready')),
  delta      int  null,
  band       text null check (band in ('below','within','above')),
  clipped    boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, metric, week_start),
  check ((status = 'calibrating' and delta is null and band is null and not clipped)
      or (status = 'ready' and delta is not null and band is not null and
          case metric when 'hrv' then delta between -30 and 30
                      when 'rhr' then delta between -10 and 10
                      else            delta between -15 and 15 end))
);  -- hrv = % vs own baseline; rhr = bpm vs own baseline; readiness = 7-day mean minus 30-day mean.

create table public.friendships (
  user_a       uuid not null references public.profiles(id) on delete cascade,
  user_b       uuid not null references public.profiles(id) on delete cascade,
  requested_by uuid not null,
  status       text not null check (status in ('pending','accepted')),
  created_at   timestamptz not null default now(),
  accepted_at  timestamptz null,
  primary key (user_a, user_b),
  check (user_a < user_b),
  check (requested_by in (user_a, user_b))
);
create index friendships_b on public.friendships(user_b);

create table public.friend_hides (            -- "Hide my data from <viewer>"; only the owner can read it
  owner  uuid not null references public.profiles(id) on delete cascade,
  viewer uuid not null references public.profiles(id) on delete cascade,
  primary key (owner, viewer)
);

create table public.invites (
  code       text primary key check (code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  used_by    uuid null references public.profiles(id) on delete set null,
  used_at    timestamptz null
);

create table public.blocks (
  blocker    uuid not null references public.profiles(id) on delete cascade,
  blocked    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked)
);

create table public.competitions (
  id           uuid primary key default gen_random_uuid(),
  created_by   uuid not null references public.profiles(id) on delete cascade,
  metric       text not null check (metric in ('steps','intensity','active','sleep_goal','bedtime')),
  mode         text not null,
  start_day    date not null,
  end_day      date not null,
  freeze_at    timestamptz not null,           -- set by create_competition: (end_day + 3) 12:00 UTC
  created_at   timestamptz not null default now(),
  finalized_at timestamptz null,
  check (end_day >= start_day and end_day - start_day <= 30),
  check (case metric when 'steps'     then mode in ('goal_percent','total','days_at_goal')
                     when 'intensity' then mode in ('goal_percent','total')
                     else mode = 'total' end)
);  -- the title is generated on the client ("Steps · Mon 6 – Sun 12 Oct"); it is never stored.

create table public.competition_members (
  competition_id uuid not null references public.competitions(id) on delete cascade,
  user_id        uuid not null references public.profiles(id) on delete cascade,
  state          text not null check (state in ('invited','joined','declined','left','removed')),
  locked_goal    int  null,                    -- steps: daily step goal; intensity: weekly goal; else null
  responded_at   timestamptz null,
  primary key (competition_id, user_id)
);
create index competition_members_user on public.competition_members(user_id);

create table public.competition_results (
  competition_id uuid not null references public.competitions(id) on delete cascade,
  user_id        uuid not null references public.profiles(id) on delete cascade,
  score          int  null,                    -- null = not sharing at freeze
  place          int  null,
  days_counted   int  not null,
  capped_days    int  not null,
  primary key (competition_id, user_id)
);

create table public.reports (
  id             bigserial primary key,
  reporter       uuid not null references public.profiles(id) on delete cascade,
  reported       uuid null references public.profiles(id) on delete set null,
  reason         text not null check (reason in ('name','cheating','harassment','other')),
  competition_id uuid null references public.competitions(id) on delete set null,
  created_at     timestamptz not null default now()
);  -- fixed reasons; no free text

create table public.rate_limits (
  user_id      uuid not null references public.profiles(id) on delete cascade,
  action       text not null,
  window_start timestamptz not null,
  count        int  not null,
  primary key (user_id, action)
);

create table public.blocked_words (word text primary key, whole_word boolean not null default false);   -- seeded at the end of the file

alter table public.profiles            enable row level security;
alter table public.share_settings      enable row level security;
alter table public.consent_log         enable row level security;
alter table public.daily_values        enable row level security;
alter table public.trend_values        enable row level security;
alter table public.friendships         enable row level security;
alter table public.friend_hides        enable row level security;
alter table public.invites             enable row level security;
alter table public.blocks              enable row level security;
alter table public.competitions        enable row level security;
alter table public.competition_members enable row level security;
alter table public.competition_results enable row level security;
alter table public.reports             enable row level security;
alter table public.rate_limits         enable row level security;
alter table public.blocked_words       enable row level security;
```

### 3.2 Helpers

All helpers are `language sql stable security definer set search_path = public`. Policies call security-definer
helpers, which avoids policy recursion (Sayner's `is_member` pattern). They live in the `private` schema, which
PostgREST does not expose, so they are not RPCs (a blocked person cannot call `is_blocked_between(blocker)` to confirm
a block, or probe `can_see(owner, metric)`); `authenticated` holds USAGE on `private` and EXECUTE on these five only,
because policy expressions run as the caller.

```sql
create function private.is_blocked_between(p_other uuid) returns boolean ... as $$
  select exists (select 1 from blocks
                 where (blocker = auth.uid() and blocked = p_other) or (blocker = p_other and blocked = auth.uid()))
$$;

create function private.are_friends(p_other uuid) returns boolean ... as $$
  select exists (select 1 from friendships
                 where user_a = least(auth.uid(), p_other) and user_b = greatest(auth.uid(), p_other)
                   and status = 'accepted')
$$;

-- THE privacy rule, defined once.
create function private.can_see(p_owner uuid, p_metric text) returns boolean ... as $$
  select p_owner = auth.uid() or (
        private.are_friends(p_owner)
    and exists (select 1 from share_settings s
                where s.user_id = p_owner and s.metric = p_metric and s.audience = 'friends')
    and not exists (select 1 from friend_hides h where h.owner = p_owner and h.viewer = auth.uid())
    and not private.is_blocked_between(p_owner))
$$;

-- Who may read whose profile row: any friendship row (pending or accepted), or a shared competition
-- in which neither side declined or was removed; never across a block.
create function private.knows(p_other uuid) returns boolean ... as $$
  select p_other = auth.uid() or (
    not private.is_blocked_between(p_other) and (
      exists (select 1 from friendships where user_a = least(auth.uid(), p_other) and user_b = greatest(auth.uid(), p_other))
      or exists (select 1 from competition_members m1 join competition_members m2 using (competition_id)
                 where m1.user_id = auth.uid() and m2.user_id = p_other
                   and m1.state in ('invited','joined','left') and m2.state in ('invited','joined','left'))))
$$;

create function private.is_competition_member(p_comp uuid) returns boolean ... as $$
  select exists (select 1 from competition_members
                 where competition_id = p_comp and user_id = auth.uid() and state in ('invited','joined','left'))
$$;
```

Internal helpers (`language plpgsql security definer set search_path = public`, never granted):
- `require_profile() returns uuid`: raises `not_signed_in` / `profile_required`, then touches `last_seen_at`.
- `bump_rate(p_action text, p_max int, p_window interval)`: raises `rate_limited`.
- `valid_name(p_name text) returns text`: applies `normalize(p_name, NFKC)`, collapses whitespace, trims, checks
  the shape and `blocked_words`, and raises `invalid_name`. A blocked word matches case-insensitively anywhere in
  the name, unless it is `whole_word`: those short ones (shit, cock, nazi, prick, …) match only as a whole word, the
  name read as runs of a–z and 0–9, so "Nazir", "Hancock" and "Yoshitaka" are names. Mirrors `DisplayName.validate`.
- `new_code() returns text`: 8 characters from `extensions.gen_random_bytes(8)` mapped onto
  `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (byte % 32).
- `finalize_competition(p_id uuid)`: takes the competition row `for update`; if `now() >= freeze_at and
  finalized_at is null`, inserts `competition_results` from the scoring CTE below and sets `finalized_at`.
- `purge_retention()`: see §3.6.

### 3.3 Policies and grants (at the end of the file, after a second blanket revoke)

```sql
revoke all on all tables in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;

create policy p_profiles    on public.profiles            for select to authenticated using (private.knows(id));
create policy p_shares      on public.share_settings      for select to authenticated using (user_id = auth.uid());
create policy p_consent     on public.consent_log         for select to authenticated using (user_id = auth.uid());
create policy p_daily       on public.daily_values        for select to authenticated using (private.can_see(user_id, metric));
create policy p_trend       on public.trend_values        for select to authenticated using (private.can_see(user_id, metric));
create policy p_friendships on public.friendships         for select to authenticated using (auth.uid() in (user_a, user_b));
create policy p_hides       on public.friend_hides        for select to authenticated using (owner = auth.uid());
create policy p_invites     on public.invites             for select to authenticated using (created_by = auth.uid());
create policy p_blocks      on public.blocks              for select to authenticated using (blocker = auth.uid());
create policy p_comps       on public.competitions        for select to authenticated using (private.is_competition_member(id));
create policy p_members     on public.competition_members for select to authenticated using (private.is_competition_member(competition_id));
create policy p_results     on public.competition_results for select to authenticated
  using (exists (select 1 from public.competition_members m
                 where m.competition_id = competition_results.competition_id and m.user_id = auth.uid()
                   and m.state in ('joined','left')));   -- final results only for people who took part
-- reports, rate_limits, blocked_words: RLS on, no policy, no grant.

grant select (id, display_name, step_goal, intensity_goal)           on public.profiles     to authenticated;
grant select (user_id, day, metric, value, source, capped)           on public.daily_values to authenticated;
grant select (user_id, metric, week_start, status, delta, band, clipped) on public.trend_values to authenticated;
grant select on public.share_settings, public.consent_log, public.friendships, public.friend_hides, public.invites,
                public.blocks, public.competitions, public.competition_members, public.competition_results
             to authenticated;
-- then one `grant execute on function public.<rpc>(<args>) to authenticated;` per public RPC in §4. Helpers used by
-- policies (can_see, knows, are_friends, is_blocked_between, is_competition_member) are granted too, because policy
-- expressions run as the caller.

-- Final check (prints; the owner eyeballs it):
select 'policies' as what, count(*) from pg_policies where schemaname = 'public'
union all select 'anon_table_grants', count(*) from information_schema.role_table_grants
  where grantee = 'anon' and table_schema = 'public'
union all select 'authenticated_write_grants', count(*) from information_schema.role_table_grants
  where grantee = 'authenticated' and table_schema = 'public' and privilege_type in ('INSERT','UPDATE','DELETE');
-- expected: policies 12, anon_table_grants 0, authenticated_write_grants 0
```

### 3.4 Metric vocabulary (Swift `FriendsMetric` raw values are identical)

| raw | Title in copy | Stored form | Rule on the phone |
|---|---|---|---|
| `steps` | Steps | daily int, cap 60,000, source strap\|phone | the funnel Home's Steps card reads (Data-source picker), one source per day; `estimate`/`import` never uploaded |
| `intensity` | Intensity minutes | daily credited minutes, cap 300 | IntradayDayStore record, `isRecorded` days only |
| `active` | Active days | 0/1 | credited ≥ 20 or a workout ≥ 20 min that local day |
| `sleep_goal` | Nights at sleep goal | 0/1 | asleep minutes ≥ `baseline.sleepGoalMinutes` (default 450) |
| `bedtime` | On-time bedtimes | 0/1 | `clockDistance(bed, SleepWindow.stored().bedMinutes) ≤ 30` |
| `hrv` | HRV trend | weekly % vs own baseline, ±30 | see §5.2 |
| `rhr` | Resting HR trend | weekly bpm vs own baseline, ±10 | see §5.2 |
| `readiness` | Readiness trend | weekly 7-day mean − 30-day mean, ±15 | see §5.2 |

The night's metrics are keyed to the wake day (Baseline's existing night key).

### 3.5 Scoring (SQL is authoritative; Swift `FriendsScoring` is a mirror)

For each joined member whose `share_settings` row for the metric still exists (at either level), with n = the
number of window days and missing days counting 0:

| metric · mode | score |
|---|---|
| steps · goal_percent | Σ_d round(least(v_d / locked_goal, 2.0) × 100), maximum 200 × n |
| intensity · goal_percent | round(least(Σ v / (locked_goal × n / 7.0), 2.0) × 100) |
| any · total | Σ v (steps, minutes, or a count of days) |
| steps · days_at_goal | count(v_d ≥ locked_goal) |

- `place = rank() over (order by score desc)` among sharing members, so ties share a place (1, 1, 3). There is no
  tiebreak; the place column prints "=1st" (VoiceOver "tied 1st") and the headline "Tied 1st of 4".
- Members who no longer share get `score = null, place = null`, and the UI shows "Not sharing".
- Members blocked in either direction relative to the viewer are filtered out of that viewer's result.
- `days_counted` = days in the window with a row; `capped_days` = rows with `capped`.

### 3.6 Retention (`purge_retention()`, scheduled by `cron.schedule('baseline-retention','17 3 * * *', 'select public.purge_retention()')`)

- `daily_values` where `day < current_date - 35`
- `trend_values` where `week_start < current_date - 35` (this leaves the current week plus 4 previous)
- `invites` where `expires_at < now() - interval '1 day'`
- `competitions` where `end_day < current_date - 90` (members and results cascade)
- `reports` older than 12 months; `rate_limits` older than 2 days
- `finalize_competition(id)` for every competition with `freeze_at <= now() and finalized_at is null`
- `auth.users` whose profile `last_seen_at < now() - interval '13 months'` (cascade: GDPR storage limitation)
- `auth.users` with no `profiles` row and `created_at < now() - interval '7 days'` (signed in with Apple, never
  chose a name; the setup sheet and Settings › Friends & sharing also offer "Delete account" in that state)

`upload()` also prunes the caller's own expired rows, so retention holds even if pg_cron is off.

### 3.7 Selftest (graft)

At the end of schema.sql, a commented `-- SELFTEST` block builds the §10 scoring fixture in a `values (...)` CTE and
asserts it with the same SQL scoring expressions. The owner can run it once without Docker or pgTAP.

## 4. RPCs (exact signatures)

Every public RPC is `security definer set search_path = public`, unless it is marked *invoker*. Each one begins
with `require_profile()` (except `complete_profile`) and a rate check, and raises stable message keys that Swift
maps through `FriendsError(rawValue:)`.

| RPC | Returns | Rules / errors | Rate |
|---|---|---|---|
| `complete_profile(p_display_name text, p_age_confirmed boolean)` | `jsonb` own profile | needs `auth.uid()`; `age_required`, `invalid_name`; idempotent (updates the name if the row already exists) | 10/h |
| `update_profile(p_display_name text default null, p_step_goal int default null, p_intensity_goal int default null)` | `void` | the step goal is stored as `greatest(p_step_goal, 3000)`, clamped to 30,000; intensity is clamped to 60–600 | 60/h |
| `set_share(p_metric text, p_audience text, p_consent_version int)` | `void` | `p_audience` null means Off: deletes the share row AND every `daily_values`/`trend_values` row for that metric, in the same transaction. Every call appends to `consent_log`. Physiology with `'competitions'` raises `invalid_audience` | 60/h |
| `upload(p_days jsonb, p_trends jsonb)` | `jsonb {accepted, dropped}` | ≤ 175 day rows and ≤ 15 trend rows per call. Rows for metrics with no share row are dropped. The day must be in `[current_date − 36, current_date + 1]` and `week_start` in `[current_date − 42, current_date + 1]`. Values over the cap are clamped and `capped = true` is set. Upsert. A day row whose `value` is null is a retraction: the caller's own row for that metric and day is deleted (the phone no longer has a shareable value for it). Prunes the caller's expired rows | 60/h |
| `my_data()` | `jsonb` | the caller's profile (all columns), shares, consent_log, daily_values, trend_values, friendships (ids and names), hides, blocks, competitions, memberships and results | 10/h |
| `create_invite()` | `jsonb {code, expires_at}` | at most 5 open (unused, unexpired) invites per person, else `invite_limit`; retries on collision | 10/day |
| `peek_invite(p_code text)` | `jsonb {display_name, expires_at}` | the same normalisation and errors as redeem, but changes nothing | 30/h |
| `redeem_invite(p_code text)` | `jsonb {friend_id, display_name}` | normalises with `upper(regexp_replace(p_code,'[^A-Za-z0-9]','','g'))`, then takes the row `for update`. Errors: `invite_invalid`, `invite_expired`, `invite_used`, `invite_self`, `blocked`, `friend_limit` (50 accepted + pending each), `already_friends`. Inserts `friendships(status 'pending', requested_by = caller)` and marks the invite used | 10/h |
| `respond_friend(p_other uuid, p_accept boolean)` | `void` | only the non-requester may respond; accept sets 'accepted' and `accepted_at`; decline deletes the row. `not_found` otherwise | 60/h |
| `set_hidden(p_other uuid, p_hidden boolean)` | `void` | inserts or deletes `friend_hides(caller, p_other)`; `not_friends` if there is no friendship row | 60/h |
| `remove_friend(p_other uuid)` | `void` | deletes the friendship row (pending or accepted) and the caller's hide row | 60/h |
| `block_user(p_other uuid)` | `void` | inserts the block; deletes the friendship and hides both ways; sets the blocked person to 'removed' in competitions the caller created that haven't ended | 30/day |
| `unblock_user(p_other uuid)` | `void` | deletes the block row | 30/day |
| `report_user(p_other uuid, p_reason text, p_competition uuid default null)` | `void` | fixed reasons; the caller must `knows(p_other)` | 20/day |
| `friends_overview(p_from date, p_to date)` *invoker* | `jsonb` | `p_to − p_from ≤ 34`, else `invalid_window`. Returns `{me, my_shares, hides, friends:[{id, display_name, step_goal, intensity_goal, status, requested_by_me}], days:[visible daily rows], trends:[visible trend rows]}`. RLS does the filtering. One scalar jsonb, so PostgREST's 1,000-row cap doesn't apply | 240/h |
| `my_competitions()` *invoker* | `jsonb` | every competition visible under RLS, with members (`user_id, display_name, state`) and the caller's state; finished ones from the last 90 days | 240/h |
| `create_competition(p_metric text, p_mode text, p_start date, p_end date, p_invitees uuid[])` | `uuid` | 1–9 invitees, each an accepted friend not blocked (`not_friends`, `too_many_participants`); `p_start ∈ [current_date − 1, current_date + 30]`; length ≤ 31 days (`invalid_window`); mode allowed (`invalid_mode`); the caller has a share row for the metric (`metric_not_shared`). Sets `freeze_at = ((p_end + 3)::timestamp + interval '12 hours') at time zone 'UTC'`. The creator joins with `locked_goal` from the profile | 10/day |
| `respond_competition(p_id uuid, p_accept boolean)` | `void` | the caller must be 'invited'. Joining is allowed while `current_date ≤ start_day + 1` (`joining_closed`) and requires a share row (`metric_not_shared`). Locks `locked_goal`. A late joiner is scored over the full window, with missing days counting 0 | 60/h |
| `leave_competition(p_id uuid)` | `void` | sets 'left'. The score stays visible as "Left" and is not ranked | 60/h |
| `remove_participant(p_id uuid, p_user uuid)` | `void` | creator only (`not_creator`); sets 'removed' | 60/h |
| `competition_standings(p_id uuid)` | `jsonb {final, freeze_at, rows:[{user_id, display_name, state, score, place, days_counted, capped_days, sharing, source_mix}], my_days:[{day, value, points, capped}]}` | `is_competition_member` (`not_member`). Calls `finalize_competition` lazily; after that it reads the frozen results. `rows` only for people taking part: a joined member while it runs, a joined or left one once final; someone invited (or who left a running one) gets the roster in `competition` and `rows: []`. `my_days` contains only the caller's own days, and is empty while only invited. `source_mix` is shown only in steps `total` mode ("strap", "phone", "strap+phone") | 600/h |
| `delete_account()` | `void` | `delete from auth.users where id = auth.uid()`, which cascades everything | 5/h |

Error keys (the complete set, which is also `FriendsError`'s raw values): `not_signed_in, profile_required,
invalid_name, age_required, invalid_audience, invite_invalid, invite_expired, invite_used, invite_self, invite_limit,
already_friends, friend_limit, blocked, rate_limited, not_found, not_friends, not_member, not_creator, joining_closed,
metric_not_shared, invalid_window, invalid_mode, too_many_participants`.

### 4.1 Edge Function `functions/delete-account/index.ts`

`POST /functions/v1/delete-account`, with the user's JWT and the body `{authorizationCode?: string}`:
1. `getUser(jwt)`; return 401 if invalid.
2. If a code was sent, build an ES256 client secret JWT: `iss=APPLE_TEAM_ID`, `kid=APPLE_KEY_ID`,
   `aud=https://appleid.apple.com`, `sub=APPLE_CLIENT_ID`, `exp=+300 s`, signed with `APPLE_PRIVATE_KEY` (a Supabase
   secret), using the `jose` module.
3. `POST https://appleid.apple.com/auth/token` (`grant_type=authorization_code`) to get the `refresh_token`.
4. `POST https://appleid.apple.com/auth/revoke` (`token_type_hint=refresh_token`). A failure is logged and never
   blocks step 5.
5. **Always** `auth.admin.deleteUser(uid)`, using `SUPABASE_SERVICE_ROLE_KEY`, which exists only in the function's
   environment.
6. Return `{deleted: true, revoked: boolean}`. No Apple token is ever stored.

### 4.2 Auth settings

- Apple provider only; Email, Phone and Anonymous are off.
- Client IDs = `com.patrickschmidt.baseline` (native id_token flow; no Services ID or secret needed).
- "Allow users without an email" on, if offered.
- JWT expiry 3600 s; refresh-token rotation on.

## 5. Client

### 5.1 Contract (`FriendsModels.swift`, `FriendsBackend.swift`, Builder B, merged first)

```swift
enum FriendsMetric: String, CaseIterable, Codable, Sendable {
    case steps, intensity, active, sleepGoal = "sleep_goal", bedtime, hrv, rhr, readiness
    var isBehaviour: Bool            // steps…bedtime
    var title: String                // "Steps", "Intensity minutes", "Active days", "Nights at sleep goal",
                                     // "On-time bedtimes", "HRV trend", "Resting HR trend", "Readiness trend"
    var sharedForm: String           // the exact consent sentence (§7.2)
    var allowedAudiences: [ShareAudience]   // physiology: [.friends]
    var dailyCap: Int?               // steps 60_000, intensity 300
}
enum ShareAudience: String, Codable, Sendable { case competitions, friends }      // nil = Off
struct DailyShare: Codable, Equatable, Sendable { var day: String; var metric: FriendsMetric; var value: Int; var source: String?; var capped: Bool }
enum TrendStatus: String, Codable, Sendable { case calibrating, ready }
enum TrendBand: String, Codable, Sendable { case below, within, above }
struct TrendShare: Codable, Equatable, Sendable { var metric: FriendsMetric; var weekStart: String; var status: TrendStatus; var delta: Int?; var band: TrendBand?; var clipped: Bool }
struct FriendsProfile: Codable, Equatable, Sendable { var id: UUID; var displayName: String; var stepGoal: Int; var intensityGoal: Int }
enum FriendStatus: String, Codable, Sendable { case accepted, pendingIncoming, pendingOutgoing }
struct Friend: Identifiable, Equatable, Sendable { var profile: FriendsProfile; var status: FriendStatus; var iHide: Bool; var days: [DailyShare]; var trends: [TrendShare]; var id: UUID { profile.id }; var lastDay: String? }
struct FriendsOverview: Equatable, Sendable { var me: FriendsProfile; var myShares: [FriendsMetric: ShareAudience]; var myDays: [DailyShare]; var friends: [Friend] }
enum CompetitionMode: String, Codable, Sendable { case goalPercent = "goal_percent", total, daysAtGoal = "days_at_goal"
    static func allowed(for metric: FriendsMetric) -> [CompetitionMode] }
enum MemberState: String, Codable, Sendable { case invited, joined, declined, left, removed }
struct CompetitionDraft: Equatable, Sendable { var metric: FriendsMetric; var mode: CompetitionMode; var start: String; var end: String; var invitees: [UUID] }
struct CompetitionMember: Equatable, Sendable { var userID: UUID; var name: String; var state: MemberState }
struct CompetitionSummary: Identifiable, Equatable, Sendable { var id: UUID; var metric: FriendsMetric; var mode: CompetitionMode; var start: String; var end: String; var createdBy: UUID; var myState: MemberState; var members: [CompetitionMember]; var freezeAt: Date; var isFinal: Bool
    var title: String }             // generated: "Steps · Mon 6 – Sun 12 Oct"
struct Standing: Identifiable, Equatable, Sendable { var userID: UUID; var name: String; var state: MemberState; var score: Int?; var place: Int?; var daysCounted: Int; var cappedDays: Int; var sharing: Bool; var sourceMix: String?; var id: UUID { userID } }
struct DayPoints: Equatable, Sendable { var day: String; var value: Int; var points: Int; var capped: Bool }
struct CompetitionStandings: Equatable, Sendable { var summary: CompetitionSummary; var rows: [Standing]; var myDays: [DayPoints]; var isFinal: Bool }
enum ReportReason: String, Codable, CaseIterable, Sendable { case name, cheating, harassment, other }
enum FriendsError: String, Error, Equatable, Sendable {
    case notSignedIn = "not_signed_in", profileRequired = "profile_required", invalidName = "invalid_name",
         ageRequired = "age_required", invalidAudience = "invalid_audience", inviteInvalid = "invite_invalid",
         inviteExpired = "invite_expired", inviteUsed = "invite_used", inviteSelf = "invite_self",
         inviteLimit = "invite_limit", alreadyFriends = "already_friends", friendLimit = "friend_limit",
         blocked, rateLimited = "rate_limited", notFound = "not_found", notFriends = "not_friends",
         notMember = "not_member", notCreator = "not_creator", joiningClosed = "joining_closed",
         metricNotShared = "metric_not_shared", invalidWindow = "invalid_window", invalidMode = "invalid_mode",
         tooManyParticipants = "too_many_participants", network, unconfigured, server
    var message: String }           // calm copy, e.g. inviteExpired → "That code has expired. Ask for a new one."
enum DisplayName { static func validate(_ raw: String) -> Result<String, FriendsError> }    // D19, mirrors SQL
enum FriendInviteCode {
    static let charset = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    static func normalize(_ raw: String) -> String?      // trim, uppercase, strip spaces/dashes, exactly 8 from charset
    static func grouped(_ code: String) -> String         // "ABCD 2345"
    static func link(_ code: String) -> URL               // baseline://friends/join/ABCD2345
    static func shareText(_ code: String) -> String
}

enum FriendsBackendKind: Sendable { case live, demo }
protocol FriendsBackend: AnyObject, Sendable {
    var kind: FriendsBackendKind { get }
    // session
    func currentUserID() async -> UUID?
    func signInWithApple(idToken: String, nonce: String) async throws
    func signInDemo() async throws                                  // demo only; live throws .unconfigured
    func signOut() async
    func deleteAccount(appleAuthorizationCode: String?) async throws -> Bool   // true = Apple token revoked
    // profile & consent
    func myProfile() async throws -> FriendsProfile?               // nil = needs profile
    func completeProfile(displayName: String, ageConfirmed: Bool) async throws -> FriendsProfile
    func updateProfile(displayName: String?, stepGoal: Int?, intensityGoal: Int?) async throws
    func setShare(_ metric: FriendsMetric, audience: ShareAudience?, consentVersion: Int) async throws
    func upload(days: [DailyShare], trends: [TrendShare]) async throws -> (accepted: Int, dropped: Int)
    func myServerData() async throws -> Data                       // my_data JSON
    // graph
    func createInvite() async throws -> (code: String, expiresAt: Date)
    func peekInvite(_ code: String) async throws -> (name: String, expiresAt: Date)
    func redeemInvite(_ code: String) async throws -> (friendID: UUID, name: String)
    func respondFriend(_ id: UUID, accept: Bool) async throws
    func setHidden(_ id: UUID, hidden: Bool) async throws
    func removeFriend(_ id: UUID) async throws
    func block(_ id: UUID) async throws
    func unblock(_ id: UUID) async throws
    func report(_ id: UUID, reason: ReportReason, competition: UUID?) async throws
    // reads
    func overview(from: String, to: String) async throws -> FriendsOverview
    // competitions
    func competitions() async throws -> [CompetitionSummary]
    func createCompetition(_ draft: CompetitionDraft) async throws -> UUID
    func respondCompetition(_ id: UUID, accept: Bool) async throws
    func leaveCompetition(_ id: UUID) async throws
    func removeParticipant(_ id: UUID, user: UUID) async throws
    func standings(_ id: UUID) async throws -> CompetitionStandings
}
```

### 5.2 Upload builder (`FriendsUploadBuilder`, pure, Builder C)

```swift
struct FriendsUploadInputs: Sendable {
    var today: String                                  // local day key
    var stepDays: [String: (value: Int, source: String)]   // source from StepsReadout.source / ResolvedMetricPoint
    var intensityDays: [String: Int]                   // credited minutes, isRecorded only
    var workoutMinutesByDay: [String: Int]             // longest workout that local day
    var nights: [String: (asleepMinutes: Int, bedMinuteOfDay: Double)]  // keyed by wake day
    var sleepGoalMinutes: Int                          // baseline.sleepGoalMinutes, default 450
    var targetBedMinutes: Int                          // SleepWindow.stored().bedMinutes
    var hrvNights: [String: Double]; var rhrNights: [String: Double]   // valid nights, last 60
    var hrvBaseline: Baselines?; var rhrBaseline: Baselines?            // Baselines.foldHistory results
    var readinessByDay: [String: Int]                  // BaselineReadouts.readinessScore
}
enum FriendsUploadBuilder {
    static func build(_ inputs: FriendsUploadInputs, shares: [FriendsMetric: ShareAudience], days: [String]) -> ([DailyShare], [TrendShare])
}
```

Rules:
- Only metrics with a share entry are built.
- **Steps:** a source of `strap` or `phone` only (the Activity spec's `StepsReadout.source`; `estimate`, `import` or a
  missing source is not counted). Read under the Data-source picker, the mode Home reads under, so an uploaded day
  matches the Steps card (imports-only shares the iPhone's count); nights, the sleep-goal and bedtime answers and
  the physiology rows follow the same picker. Values over 60,000
  become 60,000 with `capped = true`.
- **Intensity:** values over 300 become 300 with `capped = true`.
- **Active:** 1 if intensity ≥ 20 or a workout ≥ 20 min. A row is emitted only for days that have an intensity record
  or a workout.
- **Sleep goal:** asleep ≥ goal → 1, else 0, for nights that exist. **Bedtime:** `clockDistance ≤ 30` → 1.
- **Trends.** Gate: at least 14 valid nights in the last 30, otherwise `status = .calibrating` (no delta). Each
  week's row uses the 7 nights ending on the upload day (for the current week) or on Sunday (previous weeks still in
  the window).
  - HRV: `round((mean7 / baseline − 1) × 100)`, clipped to ±30.
  - RHR: `round(mean7 − baseline)`, clipped to ±10.
  - Readiness: `round(mean7(score) − mean30(score))`, clipped to ±15.
  - `clipped` is set when the value was clipped.
  - Band: from `Baselines.deviation`: |z| < 1 → within, else above/below. For readiness, |delta| < 5 → within.
- Encoded JSON keys are only `day, metric, value, source, capped, week_start, status, delta, band, clipped`. A golden
  test enforces this.

### 5.3 State and scheduling (`FriendsStore`, Builder C)

`@MainActor final class FriendsStore: ObservableObject`, created in `BaselineApp` and injected as an
`environmentObject`.

- `@Published phase: Phase` with `.unavailable`, `.signedOut`, `.needsProfile`, `.needsConsent`, `.ready`.
- `@Published overview: FriendsOverview?`, `competitions: [CompetitionSummary]`, `lastError: FriendsError?`,
  `pendingJoinCode: String?`, `isDemo: Bool`.
- `badgeCount` = incoming requests + invited competitions.
- `muted: Set<UUID>` (UserDefaults `baseline.friends.muted`, local only).
- **Friends' data lives in memory only.** Nothing about other people is written to disk.
- `needsConsent` is shown once after the profile is created; "Share nothing for now" moves to `.ready` with no shares.
  `baseline.friends.consentShown` (Bool) prevents re-prompting.

`FriendsBackendFactory.choose(config: FriendsConfig?, sampleDataActive: Bool, arguments: [String], isDebug: Bool,
previewRequested: Bool) -> Choice` (`.demo(signedIn: Bool)`, `.live(FriendsConfig)`, `.unavailable`), in order:
1. `--ui-testing`, `--friends-demo`, `--friends-state …` or `--demo-seed` (DEBUG) → `.demo`. The signed-in state
   follows `--friends-state` (`signedOut` / `setup` / `ready`, default `ready`).
2. `sampleDataActive` → `.demo(signedIn: true)`, with a "Demo friends" pill. This holds even when a config exists.
3. A valid config → `.live`.
4. `previewRequested` (the intro button, session only) → `.demo(signedIn: true)`.
5. Otherwise → `.unavailable`. The intro shows "Preview with demo friends" in both DEBUG and Release.

The choice is re-evaluated when the sample-data toggle changes. `FriendsStore` resets its memory whenever it does.

**Upload scheduler**, `scheduleUpload(force: Bool = false)`:
- Triggers:
  - `repo.$refreshSeq` (debounced 30 s, only while `scenePhase == .active`)
  - scene becoming active
  - sign-in / profile completed
  - any share change (force)
  - a change to `baseline.stepGoal`, `baseline.intensityGoalMinutes` or `baseline.sleepGoalMinutes` (also calls
    `updateProfile`)
- Throttle: at most once every 10 minutes unless forced.
- Window: 35 days (and 5 weeks of trends) on the first upload after sign-in or when a metric turns on. Otherwise
  today, the last 2 days, and any day whose value changed against the local digest `baseline.friends.uploadDigest`
  (a `[String: Int]` of hashes keyed `metric|day`, no values). A digest key inside the window that no longer has a
  row (phone steps deleted from Apple Health, a night edited away), for a metric still shared, is sent as a
  retraction (`{day, metric, value: null}`) and leaves the digest once accepted.
- Hard no-op when the backend is not live, nobody is signed in, there are no shares, sample data is active, or under
  `--ui-testing`. The demo backend receives the same payload in memory.
- No background uploads in v1.

**Sign out:** `/auth/v1/logout`, then clears the Keychain, memory, digest, muted list and `consentShown`.
**Delete:** `AppleSignIn.reauthorizeForDeletion()` → `deleteAccount(code)`. If the function fails or returns 404,
the `delete_account` RPC runs instead. Then the same local wipe.

### 5.4 Live transport (Builder B)

- **`FriendsConfig.load(bundle:) -> FriendsConfig?`** reads `Supabase.plist` (`SUPABASE_URL`,
  `SUPABASE_ANON_KEY`). It returns nil when:
  - the file is missing;
  - a placeholder (`YOUR-PROJECT`, `PASTE_`) is still in place;
  - the URL is not https;
  - the key starts with `sb_secret_`;
  - the key is a JWT whose payload `role == "service_role"`.

  `sb_publishable_…` keys and JWTs with role `anon` are accepted. It never calls `fatalError`.
- **`actor SupabaseREST`**:
  - Session: `URLSessionConfiguration.ephemeral` with `urlCache = nil`, `httpCookieStorage = nil`, and a 15 s timeout.
  - Endpoints:
    - `POST /auth/v1/token?grant_type=id_token` with `{provider:"apple", id_token, nonce}` (the raw nonce)
    - `POST /auth/v1/token?grant_type=refresh_token`
    - `POST /auth/v1/logout`
    - `POST /rest/v1/rpc/{name}`
    - `POST /functions/v1/delete-account`
  - Headers: `apikey`, `Authorization: Bearer`, `Content-Type: application/json`.
  - Token refresh: proactive when expiry is under 60 s away, single flight. One retry after a 401.
  - Errors: PostgREST `{code, message}` → `FriendsError(rawValue: message) ?? .server`. `URLError` → `.network`.
  - snake_case JSON; day keys stay Strings.
- **`FriendsKeychain`**: generic password, service `com.patrickschmidt.baseline.friends`,
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable = false`. Holds
  `{access, refresh, expiresAt, userID}`. The service name is injectable for tests. Keychain items survive deleting
  the app, so the first launch of an install (no `baseline.friends.installMarker` in UserDefaults, and none of the
  Friends keys a set-up install writes) deletes a session a previous install left before the live backend is made:
  a reinstall starts signed out instead of resuming uploads.
- **`AppleSignIn`**:
  - The nonce is created once per appearance (`SecRandomCopyBytes`); `request.nonce = sha256Hex(nonce)`.
  - `requestedScopes = []`.
  - `.canceled` is silent.
  - `reauthorizeForDeletion() async -> String?` returns `authorizationCode` as a UTF-8 string.

### 5.5 Demo backend (`LocalDemoFriendsBackend`, an actor, Builder B)

- In memory, never persisted, no network, no Keychain.
- Seeded friends Alex, Jordan, Priya and Sam (accepted), plus a pending incoming request from Chris.
- Goals: 6,000 / 8,000 / 10,000 / 7,500, so % of goal visibly differs from totals.
- Values are deterministic from a SplitMix64 hash of `(name, day key)`.
- Sharing per friend:
  - Priya shares no physiology.
  - Sam's physiology is calibrating.
  - Jordan shares steps only at the competitions level, so Jordan is absent from the board and present in
    competitions.
- Competitions:
  - active: steps · goal_percent, Mon–Sun this week, you + Alex, Jordan, Priya
  - invitation from Alex: intensity · total, next week
  - finished: bedtime · total, last week, Final, with "Tied 1st"
- Codes: `DEMO2345` → Casey (pending outgoing); `XPRDCDE2` → `invite_expired`; `USEDCDE2` → `invite_used`; the
  code `createInvite()` returned → `invite_self`; anything else valid → `invite_invalid`.
- Enforces the same rules as the SQL: Off deletes rows, `metric_not_shared`, block removes the friendship, hide,
  joining closes after start + 1, `not_creator`.
- Scores with `FriendsScoring`. Your own rows come from the real `FriendsUploadBuilder` over the local funnel.
- `signInWithApple` is unavailable; `signInDemo()` signs in as "You".

### 5.6 Tabs and deep links (Builder D)

- `BaselineRoot.Tab` gains `.friends`: label "Friends", symbol `person.2`, `.badge(friends.badgeCount)`, placed
  after Sleep.
- `LaunchRequest.parse` accepts `--tab friends`.
- `BaselineDeepLink` (in `Baseline/App/BaselineWidgetSnapshot.swift`, Foundation only because the widget compiles
  it):
  - `Destination` gains `.friends` and `.join(String)`.
  - `baseline://friends` → `.friends`.
  - `baseline://friends/join/<code>` → `.join(normalized)`; an invalid code → `.friends`.
  - Widget links are unchanged.
- An incoming `.join` selects the Friends tab and sets `pendingJoinCode`. Once the phase is `.ready`, the app calls
  `peekInvite` and shows "Connect with Sam?" with Connect / Not now.

## 6. Screens

The design contract is DESIGN.md: light paper, flat white 28 pt cards, bars and rows, **no rings anywhere on the
tab**. Liquid Glass is used only for the pinned `BaselineSegmentedPicker(style: .glass)` "Friends | Compete" and the
system bars. The toolbar has `person.badge.plus` (Friends segment: "Invite a friend" / "Enter a code") and the
Settings gear. Screens never compute competition scores; boards come from `FriendsBoard`.

1. **Intro** (signed out; `friends-intro`). One card, "Compete on what you do, not on your body", with three icon
   rows:
   - "You choose what to share: steps, intensity minutes, active days, nights at your sleep goal, on-time
     bedtimes. Nothing is shared until you turn it on."
   - "HRV, resting HR and readiness: only as your change against your own baseline, like 'HRV +8 %'. Never your
     numbers, never ranked."
   - "Never shared: heart-rate data, stress, calories, journal, location."

   Below the card:
   - `SignInWithAppleButton(.continue)`, black, 50 pt (`friends-signin`), shown only when the backend is live.
   - Caption: "Friends needs Sign in with Apple. Everything else in Baseline works without an account. Your email
     is not requested. 16 and over."
   - "Preview with demo friends" (`friends-preview`), shown when live is unavailable.
   - In demo mode: "Continue with demo account".
2. **Setup sheet** (`friends-setup`), three steps:
   - (a) Name: field "First name or nickname", caption "Friends see only this name. No photo, no email.", with
     inline `DisplayName` errors.
   - (b) Toggle "I'm 16 or older" (required), caption "Friends is for people 16 and over."
   - (c) `FriendsConsentView` (§7.2): 8 rows, each with an Off / Only in competitions / Friends menu. Every row
     starts Off. Below them, the consent paragraph; "I agree" (enabled when at least one row is on) and "Share
     nothing for now".
3. **Friends segment** (`friends-list`), cards in order:
   - a. **Requests** (only when pending): "Chris wants to connect" Accept / Decline, plus a "…" menu with Report…
     (`report_user`, allowed while the request is pending) and Block (`block_user`), so a sender's name can be
     reported and blocked before any decline (App Store 1.2); "Waiting for Casey to accept" with a Cancel button
     (`remove_friend`).
   - b. **Leaderboard** (`friends-leaderboard`):
     - Chips: the behaviour metrics that you and at least one friend share at the Friends level.
     - A flat segmented "This week | 4 weeks"; for Steps also "% of own goal | Total".
     - The headline (competitive view on): "You're 2nd of 5 · 6 % behind Alex", the gap in the rows' own unit, "Tied 1st of 5", or "You're 1st
       of 5".
     - Rows: the place ("1st", "=2nd"; VoiceOver "tied 2nd"), an initials circle, the name ("You" in bold, row
       tinted accent 0.14), a bar, and the value ("84 % of own goal · 9,010 a day", "52,310 steps", "112 min",
       "5 of 7 nights").
     - Never HRV, resting HR or readiness, not even as an unranked chip: they live only on the alphabetical friend
       cards (c) and the friend detail. With only physiology shared, the card is its empty state.
     - Captions: "Ranked on what you do. HRV, resting HR and readiness are never ranked." and "2 friends don't share
       steps".
     - If you don't share the metric: "Share Steps with friends to appear here" with a chevron to Settings.
     - Competitive view off: alphabetical, no places, no headline.
   - c. **FriendWeekCard** per accepted friend, **alphabetical** (`friend-row-<name>`):
     - Name, plus "Updated today / yesterday / 3 days ago".
     - Mon–Sun goal-day dots for their first shared behaviour metric (filled = at own goal, hollow = missed, faint =
       future or no data), plus 7 thin bars with their own goal tick.
     - Neutral pills: "HRV +8 % vs own baseline", "Resting HR −2 bpm vs own baseline", "Readiness +4 vs own month",
       "HRV · calibrating", and "≥ +30 %" / "≤ −30 %" when clipped (the sign picks the bound).
     - Muted friends collapse into "Muted (n)".
   - d. **Empty** (no friends): "Invite a friend. They'll get a code to enter in Baseline. You both choose what to
     share." with Invite / Enter code.
4. **Friend detail** (`friend-detail`):
   - "This week": a bar block per shared behaviour metric.
   - "Trends": one sentence per shared physiology metric ("HRV is 8 % above Alex's own baseline, within their usual
     range.") plus up to 5 weekly points on a zero line labelled "own baseline", neutral ink, with the footnote
     "Each person against their own baseline. Not comparable between people."
   - "Together": shared competitions.
   - "Manage": "Hide my data from Alex", "Mute", "Remove friend", "Block", "Report…" (Inappropriate name / Cheating
     / Harassment / Other). Destructive actions go through a confirmationDialog.
5. **Invite sheet** (`friends-invite`):
   - The code grouped "ABCD 2345" in monospaced rounded type, with "Single use · expires Thu 9 Oct".
   - `ShareLink`: "Connect with me on Baseline: enter ABCD2345 in Friends, or open baseline://friends/join/ABCD2345".
   - Copy, and the caption "Codes never show your health data."

   **Enter code sheet** (`friends-enter-code`): 8 characters, auto-uppercased, ignores dashes and spaces. The peek
   asks "Connect with Sam?" and confirms "Request sent to Sam."
6. **Compete segment** (`compete-list`):
   - "New competition" `BaselineCTA` (`compete-new`).
   - Invitations: "Alex invited you · Intensity minutes · Mon 13 – Sun 19 Oct" with Join / Decline. Joining an
     unshared metric first shows a sheet: "Share Intensity minutes for competitions only? Your daily minutes are
     used for scoring in competitions you join; friends outside them don't see them."
   - Active cards (`competition-card`): generated title, one-line mode, your place, top 3 bars, "3 days left".
   - Finished (last 90 days): a "Final" pill and "Rematch".
   - Copy names: "Week of steps", "Weekday steps", "Weekend steps", "Days at goal".
7. **Create sheet** (`compete-create`):
   - Metric chips (the 5 behaviour metrics) and mode chips with one line each:
     - % of own goal: "Each day's steps as a share of your own goal, up to 200 a day. Fair across different goals."
     - Total: "Raw steps, capped at 60,000 a day; each person's source is shown."
     - Days at goal: "Days you reach your own goal. Everyone can win."
   - When: This week / Next week / Weekdays / Weekend / Custom (≤ 31 days).
   - Who: friends with checkmarks, up to 9, captioned "They'll see your score in this competition only."
   - Summary: "Steps · % of own goal · Mon 6 – Sun 12 Oct, each in your own time zone · goals lock when you join."
8. **Competition detail** (`competition-standings`):
   - Header with the rule ("Points = your steps ÷ your own goal × 100 each day, at most 200").
   - Standings rows (grey "Not sharing" / "Left").
   - "Your days" bars with a "capped" mark, in the rule's own unit: points with a line at 100 (steps · % of own
     goal), minutes with a line at the weekly goal ÷ 7 (intensity · % of own goal, scored over the whole window),
     steps / minutes (total), full or empty bars ("At goal" / "Missed", active days, nights). VoiceOver reads the
     same words.
   - Steps · total: "Counted by: You, strap and iPhone · Alex, strap".
   - Rules card: "Your goal is locked at 8,000 when you join. Each person's own day counts, in their own time zone.
     Results become final on Wed 15 Oct." (the `freeze_at` date the status prints; the time-zone sentence is not
     repeated on the Invitation card).
   - "Day 4 of 7", then "Final on Wed 15 Oct", then "Final".
   - Leave; for the creator, Remove a participant; Report; Rematch once final.
9. **Settings › Friends & sharing** (new `SettingsSection(label: "Friends")` between Notifications and About;
   `settings-friends`):
   - Signed out: "Not signed in. Friends is optional." with a chevron to the tab.
   - Signed in (any phase from `.needsProfile` on; the screen branches on the phase, never on whether the overview
     loaded):
     - Name (edit), and "Competitive view" (caption "Off shows friends alphabetically, without places").
     - "What you share": the 8 rows (`share-menu-<metric>`). Turning one off confirms "Stop sharing Steps? Its
       values are deleted from the server now." Turning one ON from Off first shows the explicit consent
       (`FriendsShareConsentSheet`: "Share HRV with friends?", the metric's shared form, the §7.2 paragraph,
       "I agree" / "Not now"); only "I agree" calls `set_share`. Moving between two on levels is a plain choice.
     - "Hidden from n".
     - "See what's on the server": SharedDataScreen with ShareLink JSON export (once a profile exists).
     - "Sign out" (no caption; its confirmation says "Friends keep seeing what you last shared until it ages out
       after 35 days or you stop sharing").
     - "Delete account and shared data" (`friends-delete`), red. After it: "Deleted. Apple sign-in for Baseline was
       revoked.", or the manual-revoke line.
     - Signed in but the overview did not load: "What you share didn't load", the error and "Try again", with the
       Account card (Sign out, Delete) still there.
     - `.needsProfile` (signed in with Apple, no name yet): "Finish setting up in the Friends tab" plus Sign out and
       Delete; the setup sheet's name step also offers "Delete account" (`friends-setup-delete`), App Store 5.1.1(v).
   - Settings › Profile gains the "Sleep goal" stepper (D16), inside the Sleep window card (`SettingsSleepWindowCard`,
     `settings-sleep-goal`), with one line saying Friends counts a night at the goal and only whether it was reached is
     shared. The value is printed wherever a night is judged against it: the consent row and the share line
     (`FriendsMetric.sharedForm`) and the sleep competition's rule (`FriendsScoring.ruleText`). A friend's own goal is
     never uploaded, so Friend detail says "their own sleep goal" without a number.

**Accessibility:**
- Every row is one combined element ("Alex, 2nd, 84 percent of goal, 48,200 steps this week").
- Bars and dots are hidden from VoiceOver; the dots' summary reads "4 of 7 goal days".
- At accessibility sizes, `ViewThatFits` stacks the value under the name.

**Vocabulary:** "Strain", "Recovery", "Coach", "Circles", "rings", "Workweek Hustle", "Weekend Warrior", "Goal Day"
and "Daily Showdown" never appear.

## 7. Privacy and compliance

### 7.1 Principles

- Art. 25: every metric is Off by default. Only the derived form goes up.
- No email, no Apple name, no photos, contacts, search, chat, push tokens or analytics.
- Friends' data is held in memory only.
- Tokens are kept ThisDeviceOnly.
- Demo, sample and UI-test modes never upload.
- No health data in iCloud/CloudKit (guideline 5.1.3(ii)).
- The service-role key is never in the app or the repo.

### 7.2 Consent copy (`consent_version = 1`)

| Metric | Shared form (exact) |
|---|---|
| Steps | your daily step count and whether the strap or iPhone counted it |
| Intensity minutes | your daily minutes, counted against your own heart rate |
| Active days | whether a day had 20+ intensity minutes or a 20-minute workout |
| Nights at sleep goal | whether a night reached your own sleep goal (7h 30m asleep, set in Settings › Profile); never hours or times |
| On-time bedtimes | whether bedtime was within 30 min of your target; never the time |
| HRV trend | weekly HRV change vs your own baseline, e.g. +8 %; never your HRV |
| Resting HR trend | weekly change vs your own baseline, e.g. −2 bpm; never your heart rate |
| Readiness trend | this week vs your month, e.g. +4; never your score |

The sleep-goal row prints the person's current goal (`BaselineReadouts.SleepGoal.text`, "7h 30m" by default). What is
shared does not change with it (one 0/1 per night), so naming the value keeps `consent_version = 1`.

The paragraph below the rows:

> "Health data. By tapping I agree, you explicitly consent to Baseline storing the items you turned on above on
> Baseline's server (Supabase, Frankfurt, EU) and showing them only to friends you accept, or only inside
> competitions you join. You can withdraw any time in Settings › Friends & sharing; withdrawing deletes them from the
> server. Daily values are kept 35 days."

Legal bases:
- Art. 9(2)(a) explicit consent, per metric, separate from the terms and never pre-ticked. Logged in
  `share_settings` and `consent_log`.
- Art. 7(3): withdrawing deletes the rows in the same transaction.
- Art. 8: 16+, stored in `age_confirmed_at`.
- Art. 15/20: `my_data` plus the JSON export.
- Art. 17: hard delete plus Apple revoke.
- Art. 28: Supabase DPA.
- Art. 30/35: a one-page record of processing and a DPIA outline in PRIVACY.md.

### 7.3 Retention

| Data | Kept |
|---|---|
| Daily values | 35 days |
| Physiology | current week + 4 |
| Invites | 7 days (+1) |
| Competitions/results | 90 days after the end |
| Reports | 12 months |
| Inactive accounts | 13 months |
| Consent log | until deletion |

The policy also discloses that Supabase API logs keep IP addresses for the plan's log window.

### 7.4 Files to update (Builder A)

- **`Baseline/PRIVACY.md`:** "Local first; Friends is optional". Covers what, why, where (Supabase Frankfurt),
  who sees it, retention, withdrawal, deletion, 16+, the reports contact `paddyr.schmidt@gmail.com`, and the DPIA
  outline. Keeps "no analytics, ads or tracking".
- **`BASELINE.md`:**
  - The "Local only" rule becomes "Local first: everything works without an account; the opt-in Friends tab
    uploads only the derived values the person picks (Baseline/Research/FRIENDS_SPEC.md)".
  - Four tabs.
  - New keys: `baseline.sleepGoalMinutes`, `baseline.friends.muted`, `baseline.friends.uploadDigest`,
    `baseline.friends.competitiveView`, `baseline.friends.consentShown`.
- **`Components/DESIGN.md`:** an IA row for Friends; the glass budget (1 pinned picker); "no rings on Friends".
- **`Resources/PrivacyInfo.xcprivacy`:** `NSPrivacyCollectedDataTypes` = Health, Fitness, Name, UserID, each
  `Linked = true`, `Tracking = false`, `[AppFunctionality]`. Add Email Address only if the D20 fallback is used. The
  widget manifest is unchanged.
- **`Store/PrivacyNutrition.md`:** "Data Not Collected" becomes "Data Linked to You", for App Functionality only:
  - Health: the deltas and the sleep/bedtime booleans
  - Fitness: steps, intensity minutes, active days
  - Contact Info › Name: the display name
  - Identifiers › User ID
- **`Store/ReviewNotes.md`:**
  - Friends is optional.
  - Try it with "Preview with demo friends" or an Apple ID.
  - Only aggregates leave the device.
  - Account deletion is in Settings › Friends & sharing.
  - Report and block are on every friend.
  - The contact email.
- **`scripts/release-check.sh`:**
  - FAIL if anything from `Backend/` or `Supabase.example.plist` is in the bundle.
  - FAIL if the bundled `Supabase.plist` key is `sb_secret_` or a JWT whose role is not `anon`.
  - FAIL on any `service_role` string in the bundle.
  - FAIL if the applesignin entitlement is present while collected types are empty.
  - WARN if Release has no `Supabase.plist`.

## 8. Security summary

- Clients have SELECT on 12 tables, filtered by RLS, and EXECUTE only on the listed RPCs. Every write is a validated
  RPC. anon can do nothing.
- Column grants hide `last_seen_at`, `age_confirmed_at`, `created_at`, `updated_at`; hides are invisible to the
  hidden person. The policy helpers live in `private`, so they are not callable RPCs.
- "Competitions only" sharing reaches co-competitors only through `competition_standings` (security definer), which
  is the trust boundary. `rpc.sql` covers it.
- Input validation: check constraints on every value, server-side caps, NFKC name filter, fixed report reasons,
  generated titles (the display name is the only user-generated content).
- Rate limits are per RPC (§4). Invites are server-generated and single use, 5 open at most.
- The client is trusted for uploaded values. That is proportionate for friends with no stakes: caps, the 3,000 goal
  floor, goals locked when you join, source shown, report, remove participant.

## 9. Builders (one pass)

- **A, server and compliance:** everything in `Baseline/Backend/supabase/` (schema, Edge Function, pgTAP, selftest,
  example plist, SETUP.md), the `project.yml` Baseline-block edits, `Resources/.gitignore`, and every §7.4 document,
  manifest and release-check change.
- **B, contract and backends:** `FriendsModels`, `FriendsBackend` (merged first, day 0), `FriendsScoring`,
  `FriendsBoard`, `FriendsBackendFactory`, `Live/*`, `AppleSignIn`, `Demo/*`, and their tests.
- **C, upload, state and settings:** `FriendsUploadBuilder`, `FriendsUploadInputs`, `FriendsStore` plus its wiring in
  `BaselineApp`, `SettingsFriends`, `SharedDataScreen`, `SettingsSleepGoal`, `FriendsConsentView` (shared with D),
  and their tests.
- **D, UI:** the 4th tab, deep links and `LaunchRequest` in `BaselineRoot`/`BaselineWidgetSnapshot`, every
  `Screens/Friends/*`, and the UI tests at normal and AX sizes.

Coordination:
- `StepsReadout.source` and `baseline.stepGoal` (default 8,000) come from the Activity builders. Until they land,
  C reads `ResolvedMetricPoint.source` and `UserDefaults` with a default of 8,000.
- `BaselineDeepLink` stays Foundation only.

## 10. Tests

**Unit (BaselineTests)**
- `FriendsScoringTests` (shared fixture with `tests/scoring.sql` and the schema SELFTEST):
  - Steps goal_percent: 12,000 against 8,000 → 150; 20,000 → 200; 7 days at 200 → 1,400.
  - Goal floor 3,000 (a 2,000 goal is stored as 3,000).
  - Intensity goal_percent for a 3-day window with a weekly goal of 150 → target 64.29; 70 min → 109.
  - Total with a 70,000 day → 60,000 and `capped_days` 1.
  - days_at_goal.
  - A late joiner's missing days count 0.
  - Ties [300, 300, 200] → places [1, 1, 3], printed "=1st" (spoken "tied 1st").
  - The same day keys give the same score under any `TimeZone`.
  - Freeze time for `end 2026-10-12` = 2026-10-15 12:00 UTC.
- `FriendsBoardTests`:
  - % of goal ordering, with total second.
  - The headline names the person directly above ("6 % behind Alex" in % of own goal, the rows' unit; never summed points); tied and first-place variants.
  - Competitive view off → alphabetical with no places.
  - Non-sharers counted in the caption.
  - Friend cards alphabetical.
  - Physiology never sorted by value.
  - Goal-day dots.
- `FriendsUploadBuilderTests`:
  - No shares → empty.
  - Only shared metrics.
  - `estimate`/`import` steps excluded; strap and phone kept with their source.
  - 70,000 → 60,000 capped.
  - Sleep goal 449 → 0, 450 → 1.
  - Bedtime 23:50 against a 00:10 target → 1.
  - Active from 20 intensity minutes or a 20-minute workout.
  - Trend gate: 13 of 30 → calibrating, 14 → ready.
  - Clips: HRV +42 → 30 with `clipped`; RHR −14 → −10.
  - Band word.
  - Weekly rows keyed to Monday.
  - **Golden JSON:** only the whitelisted keys appear.
- `FriendsStoreTests` (recording fake backend):
  - Phase machine.
  - No upload when unshared, on sample data, under `--ui-testing`, or on demo.
  - 35-day window after a metric turns on, then the incremental window plus changed days.
  - The 10-minute throttle, with force bypassing it.
  - Sign-out wipe.
  - Delete falls back to the RPC.
  - `pendingJoinCode` survives sign-in and triggers a peek.
- `FriendsBackendFactoryTests`:
  - Sample data → demo even with a config.
  - `--demo-seed` → demo.
  - `--friends-state signedOut` → `demo(signedIn: false)`.
  - Config → live.
  - None → unavailable; preview → demo.
- `FriendsConfigTests`:
  - missing, placeholder, http, `sb_secret_`, or a `service_role` JWT → nil
  - an anon JWT or `sb_publishable_` → config
- `FriendsModelsTests`:
  - `DisplayName`: "Ana-María", "J.R." valid; "a", 25 characters, "x@y", "www.site" and a blocked word invalid.
  - `FriendInviteCode.normalize(" abcd-2345 ")` → "ABCD2345"; codes containing O, 0, 1 or I → nil.
  - Link round trip.
  - `CompetitionMode.allowed`.
  - `FriendsError` raw values match the SQL key list.
- `SupabaseRESTTests` (stub URLProtocol):
  - id_token body and headers.
  - Proactive refresh; 401 → refresh → one retry.
  - `{message:"invite_expired"}` → `.inviteExpired`.
  - Ephemeral session with no URLCache.
  - Keychain round trip under a test service name.
- `LocalDemoFriendsBackendTests`:
  - Full flow: sign in → profile → share → invite → peek → redeem (pending) → accept → create → standings.
  - The `XPRDCDE2`/`USEDCDE2`/own-code errors.
  - Off deletes rows.
  - `metric_not_shared` on join.
  - Block removes the friendship.
  - Hide hides.
  - Deterministic seed.
- `BaselineRootLaunchTests`: `--tab friends`. `WidgetSnapshotTests`: `baseline://friends`,
  `baseline://friends/join/abcd2345` → `.join("ABCD2345")`, an invalid code → `.friends`, widget links unchanged.

**Server (pgTAP, `supabase test db`)**
- `rls.sql`:
  - B cannot read A's rows until the friendship is accepted AND A shares at the friends level.
  - The competitions level is invisible in `daily_values` but counted in standings.
  - Hide and block both cut visibility.
  - Stranger C sees nothing, including A's profile.
  - B selecting `profiles.last_seen_at` errors.
  - Every insert, update and delete from `authenticated` is denied.
  - anon can execute no function.
- `rpc.sql`:
  - Invite expiry, single use, self, friend cap, rate limits.
  - Peek changes nothing.
  - Upload drops unshared metrics and out-of-window days.
  - Check constraints reject 70,001 steps and HRV 31.
  - `set_share(null)` deletes the rows.
  - A late join after start + 1 is refused.
  - `remove_participant` only by the creator.
  - Finalising happens at `freeze_at` and the results are immutable afterwards.
  - `delete_account` leaves zero rows for that user in every table.
- `scoring.sql`: the shared fixture.

**UI (ScreenshotTests via `Baseline/scripts/ui-shots.sh`, and again with `AX=1`)**
- `testFriendsIntro` (`--tab friends --friends-state signedOut`)
- `testFriendsSetup` (`--friends-state setup`)
- `testFriends`: friends-0, friends-1, friend-detail, invite-sheet
- `testEnterCodeErrors`: `XPRDCDE2` shows the expired copy; `DEMO2345` shows "Waiting for Casey to accept"
- `testCompete`: compete-0, competition-detail, compete-create
- `testSettingsFriends`
- Assertions:
  - No "ms" or raw HRV value on any Friends screen.
  - Friend cards are alphabetical.
  - The leaderboard caption is present.
  - None of the banned words appear.
  - At AX3, no truncated names and the rows stack.

## 11. Owner steps (Patrick; the tab works on demo friends before any of this)

1. **Check the developer account type** for team 25RC553RGP (developer.apple.com › Membership). Guideline
   5.1.1(ix) expects an organisation for sensitive health data. If the account is Individual, either ship Release
   without `Supabase.plist` (the tab offers the demo preview only) or accept the risk knowingly.
2. **Create the Supabase project.** supabase.com → New project "baseline-friends", region **Central EU
   (Frankfurt)**, a strong DB password in your password manager. **Pro plan** is recommended, because free projects
   pause after about 7 idle days. Sign the DPA (Organization › Legal documents).
3. **Run the schema.** Database › Extensions: enable **pg_cron**. SQL editor: paste and run
   `Baseline/Backend/supabase/schema.sql`. The final query must print `policies 12, anon_table_grants 0,
   authenticated_write_grants 0`. Optionally run the commented SELFTEST block.
4. **Turn on the Apple provider.** Authentication › Sign In / Providers:
   - Disable Email, Phone and Anonymous.
   - Enable **Apple** with Client IDs = `com.patrickschmidt.baseline`; no secret key is needed for native sign-in.
   - Turn on "Allow users without an email" if offered. If it isn't, tell a builder to switch on the D20 fallback.
   - Authentication › Sessions: JWT expiry 3600, refresh-token rotation on.
5. **Register the capability.** Apple Developer › Identifiers › `com.patrickschmidt.baseline`: enable **Sign in with
   Apple** (Enable as primary App ID) and save. Xcode's automatic signing then regenerates the profile.
6. **Create a Sign in with Apple key.** Apple Developer › Keys › "+": name it "Baseline Sign in with Apple", tick
   Sign in with Apple, configure it for `com.patrickschmidt.baseline`, and register. Download the `.p8` **once**
   and note the Key ID.
   - Create a **new** key; never reuse or open Sayner's.
   - Keep the `.p8` out of every repo.
7. **Deploy the delete-account function.** `brew install supabase/tap/supabase`, then from
   `Baseline/Backend`: `supabase login` → `supabase link --project-ref <ref>` →
   `supabase secrets set APPLE_TEAM_ID=25RC553RGP APPLE_KEY_ID=<key id> APPLE_CLIENT_ID=com.patrickschmidt.baseline APPLE_PRIVATE_KEY="$(cat ~/path/AuthKey_<id>.p8)"`
   → `supabase functions deploy delete-account`. The service-role key is injected automatically; never copy it
   anywhere.
8. **Add the app config.** Copy `Baseline/Backend/supabase/Supabase.example.plist` to
   `Baseline/Resources/Supabase.plist`. Paste the Project URL (`https://<ref>.supabase.co`) and the
   anon/publishable key (Settings › API). **Never** use the service_role or secret key; the app refuses them.
   `git status` must show the file as ignored.
9. **Build.** Run `xcodegen generate` and build to a device. Smoke test with a second Apple ID:
   - code → peek → redeem → accept
   - share Steps → see each other
   - create a steps competition
   - turn Steps off → the friend's row disappears
   - delete one account → the dashboard shows zero rows for that id
10. **Optional:** Docker + `supabase start && supabase test db` runs the RLS, RPC and scoring tests.
11. **App Store Connect.**
    - Update App Privacy exactly as in `Store/PrivacyNutrition.md`.
    - Re-answer the age-rating questionnaire (display names as user-generated content, with report and block).
    - Paste the new `ReviewNotes.md`.
    - Publish the updated privacy policy.
    - Check the `reports` table weekly; to act on a report, block or delete the profile from the dashboard.
12. **Keep the DPIA and record of processing** (outline in PRIVACY.md).

## 12. Risks

1. **Guideline 5.1.1(ix) on an individual account.** This is the largest risk. Mitigated by aggregates only, the
   review notes, and a Release build that can ship without a config (demo preview).
2. **Supabase may refuse Apple users without an email.** Fallback D20: one line in AppleSignIn, plus the manifest
   and label.
3. **Supabase default grants.** Handled by revokes at both ends of schema.sql, the final grant query, and `rls.sql`.
4. **Manually entered Apple Health steps** can't be filtered without editing NOOP's HealthKitBridge. Accepted: caps,
   the source is shown, goal-% is the default, no prizes. Propose an upstream PR.
5. **No background upload** in v1. Friends see "Updated yesterday", and the 48 h freeze absorbs late syncs. A
   BGAppRefresh upload comes in v1.1.
6. **`baseline://` links** aren't tappable everywhere; the code is the reliable path. Universal links are v1.1.
7. **Revocation needs a fresh Apple authorization code.** If the person cancels, the data is still hard-deleted via
   the RPC and the copy explains manual revocation.
8. **`competition_standings` is the trust boundary** for competition-only sharing; `rpc.sql` must cover the member,
   share and block filters.
9. **The applesignin entitlement** breaks device builds until owner step 5. Simulator builds and UI tests are
   unaffected.
10. **SQL vs Swift scoring drift.** Guarded by one fixture in three places (Swift tests, `scoring.sql`, SELFTEST).
11. **Weekly physiology rows** could hint at a sustained change. Mitigated: 7-day means, clipping, 5 weeks max,
    alphabetical display, never ranked or notified, and Off by default.
12. **Deferred on purpose (v1.1+):** improvement and together modes, reactions, push, photos, search, free-text
    titles, background upload, universal links, head-to-head record, recurrence. Physiology competitions are never
    built.
