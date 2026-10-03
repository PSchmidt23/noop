-- =====================================================================================================================
-- Baseline Friends: Supabase schema (FRIENDS_SPEC.md §3–§4)
--
-- Run once in the Supabase SQL editor of the project "baseline-friends" (region Central EU / Frankfurt), AFTER
-- enabling pg_cron under Database › Extensions. Re-running is safe: tables use IF NOT EXISTS, functions are
-- CREATE OR REPLACE, policies are dropped and recreated. The last query must print:
--     policies 12 · anon_table_grants 0 · authenticated_write_grants 0 · api_policy_helpers 0
--
-- The rules this file enforces:
--   * Clients write NOTHING directly. Every INSERT/UPDATE/DELETE goes through a SECURITY DEFINER RPC that validates
--     its input. Supabase's default grants are revoked at the top AND again at the end.
--   * Clients read through 12 SELECT-only RLS policies. The one privacy rule for health rows is can_see(owner, metric).
--   * Behaviour is shared as capped daily integers (steps, intensity minutes) or 0/1 (active day, sleep goal,
--     on-time bedtime). Physiology is one clipped weekly change against the owner's OWN baseline. Never raw HRV,
--     heart rate, clock times, calories or stress.
--   * Nothing is shared until the owner turns a metric on; turning it off deletes its rows in the same transaction.
--   * Day keys are each person's LOCAL calendar date. The server never converts time zones.
--
-- Error keys the RPCs raise, or (peek_invite, redeem_invite) return as {"error": key} so their rate limit still counts
-- a refused call (Swift FriendsError raw values): not_signed_in, profile_required, invalid_name,
-- age_required, invalid_audience, invite_invalid, invite_expired, invite_used, invite_self, invite_limit,
-- already_friends, friend_limit, blocked, rate_limited, not_found, not_friends, not_member, not_creator,
-- joining_closed, metric_not_shared, invalid_window, invalid_mode, too_many_participants.
-- =====================================================================================================================

-- ---------------------------------------------------------------------------------------------------------------------
-- 0. Extensions and lockdown
-- ---------------------------------------------------------------------------------------------------------------------
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_cron;

revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

-- Internal helpers live in a schema PostgREST does not expose, so they can never be called over the API.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
alter default privileges in schema private revoke execute on functions from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------------------------------------------------
create table if not exists public.profiles (
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

create table if not exists public.share_settings (
  user_id         uuid not null references public.profiles(id) on delete cascade,
  metric          text not null check (metric in ('steps','intensity','active','sleep_goal','bedtime','hrv','rhr','readiness')),
  audience        text not null check (audience in ('competitions','friends')),
  consent_version int  not null check (consent_version >= 1),
  granted_at      timestamptz not null default now(),
  primary key (user_id, metric),
  check (metric not in ('hrv','rhr','readiness') or audience = 'friends')
);  -- no row = Off. The row is the live consent record.

create table if not exists public.consent_log (
  id        bigserial primary key,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  metric    text not null,
  audience  text null,           -- null = withdrawn
  version   int  not null,
  at        timestamptz not null default now()
);
create index if not exists consent_log_user on public.consent_log(user_id);

create table if not exists public.daily_values (
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
create index if not exists daily_values_day on public.daily_values(day);

create table if not exists public.trend_values (
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

create table if not exists public.friendships (
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
create index if not exists friendships_b on public.friendships(user_b);

create table if not exists public.friend_hides (            -- "Hide my data from <viewer>"; only the owner can read it
  owner  uuid not null references public.profiles(id) on delete cascade,
  viewer uuid not null references public.profiles(id) on delete cascade,
  primary key (owner, viewer)
);

create table if not exists public.invites (
  code       text primary key check (code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  used_by    uuid null references public.profiles(id) on delete set null,
  used_at    timestamptz null
);
create index if not exists invites_creator on public.invites(created_by);

create table if not exists public.blocks (
  blocker    uuid not null references public.profiles(id) on delete cascade,
  blocked    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked)
);

create table if not exists public.competitions (
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

create table if not exists public.competition_members (
  competition_id uuid not null references public.competitions(id) on delete cascade,
  user_id        uuid not null references public.profiles(id) on delete cascade,
  state          text not null check (state in ('invited','joined','declined','left','removed')),
  locked_goal    int  null,                    -- steps: daily step goal; intensity: weekly goal; else null
  responded_at   timestamptz null,
  primary key (competition_id, user_id)
);
create index if not exists competition_members_user on public.competition_members(user_id);

create table if not exists public.competition_results (
  competition_id uuid not null references public.competitions(id) on delete cascade,
  user_id        uuid not null references public.profiles(id) on delete cascade,
  score          int  null,                    -- null = not sharing at freeze
  place          int  null,
  days_counted   int  not null,
  capped_days    int  not null,
  primary key (competition_id, user_id)
);

create table if not exists public.reports (
  id             bigserial primary key,
  reporter       uuid not null references public.profiles(id) on delete cascade,
  reported       uuid null references public.profiles(id) on delete set null,
  reason         text not null check (reason in ('name','cheating','harassment','other')),
  competition_id uuid null references public.competitions(id) on delete set null,
  created_at     timestamptz not null default now()
);  -- fixed reasons; no free text

create table if not exists public.rate_limits (
  user_id      uuid not null references public.profiles(id) on delete cascade,
  action       text not null,
  window_start timestamptz not null,
  count        int  not null,
  primary key (user_id, action)
);

create table if not exists public.blocked_words (   -- seeded at the end of the file
  word       text primary key,
  whole_word boolean not null default false           -- true: matches only as a whole word (see private.valid_name)
);
alter table public.blocked_words add column if not exists whole_word boolean not null default false;

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

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Policy helpers (security definer: they read past RLS, which avoids policy recursion). They live in the private
--    schema, which PostgREST does not expose, so they are not RPCs: a blocked person cannot call
--    is_blocked_between(blocker) to confirm a block, or probe can_see(owner, metric) for someone's sharing. Policy
--    expressions run as the caller, so authenticated holds USAGE on private and EXECUTE on these five (section 7).
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function private.is_blocked_between(p_other uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from blocks
                 where (blocker = auth.uid() and blocked = p_other) or (blocker = p_other and blocked = auth.uid()))
$$;

create or replace function private.are_friends(p_other uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from friendships
                 where user_a = least(auth.uid(), p_other) and user_b = greatest(auth.uid(), p_other)
                   and status = 'accepted')
$$;

-- THE privacy rule, defined once.
create or replace function private.can_see(p_owner uuid, p_metric text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_owner = auth.uid() or (
        private.are_friends(p_owner)
    and exists (select 1 from share_settings s
                where s.user_id = p_owner and s.metric = p_metric and s.audience = 'friends')
    and not exists (select 1 from friend_hides h where h.owner = p_owner and h.viewer = auth.uid())
    and not private.is_blocked_between(p_owner))
$$;

-- Who may read whose profile row: any friendship row (pending or accepted), or a shared competition in which neither
-- side declined or was removed; never across a block.
create or replace function private.knows(p_other uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_other = auth.uid() or (
    not private.is_blocked_between(p_other) and (
      exists (select 1 from friendships where user_a = least(auth.uid(), p_other) and user_b = greatest(auth.uid(), p_other))
      or exists (select 1 from competition_members m1 join competition_members m2 using (competition_id)
                 where m1.user_id = auth.uid() and m2.user_id = p_other
                   and m1.state in ('invited','joined','left') and m2.state in ('invited','joined','left'))))
$$;

create or replace function private.is_competition_member(p_comp uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from competition_members
                 where competition_id = p_comp and user_id = auth.uid() and state in ('invited','joined','left'))
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Internal helpers (schema private; never reachable over the API)
-- ---------------------------------------------------------------------------------------------------------------------

-- The caller's id, after checking they are signed in and have a profile. Touches last_seen_at (at most hourly), which
-- drives the 13-month inactive-account purge.
create or replace function private.require_profile() returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not_signed_in'; end if;
  if not exists (select 1 from profiles where id = v_me) then raise exception 'profile_required'; end if;
  update profiles set last_seen_at = now() where id = v_me and last_seen_at < now() - interval '1 hour';
  return v_me;
end $$;

-- A fixed-window rate limit per (caller, action). Raises rate_limited once the window holds p_max calls.
-- The bump commits only with its caller: an RPC that later RAISES rolls it back, so a failure never counts. Where
-- failures are what the limit is for (guessing invite codes), the RPC returns {"error": key} instead of raising.
create or replace function private.bump_rate(p_action text, p_max int, p_window interval) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_count int;
begin
  insert into rate_limits(user_id, action, window_start, count)
  values (auth.uid(), p_action, now(), 1)
  on conflict (user_id, action) do update set
    window_start = case when rate_limits.window_start < now() - p_window then now() else rate_limits.window_start end,
    count        = case when rate_limits.window_start < now() - p_window then 1 else rate_limits.count + 1 end
  returning count into v_count;
  if v_count > p_max then raise exception 'rate_limited'; end if;
end $$;

-- Display name (D19): NFKC, whitespace collapsed, trimmed; 2–24 characters; no control characters, < > @ / \ :,
-- "http" or "www."; no blocked word. A blocked word matches case-insensitively, anywhere in the name, unless it is
-- marked whole_word: those match only as a whole word, the name read as runs of a–z and 0–9 with everything else a
-- separator, so "Nazir", "Hancock" and "Yoshitaka" are names and "Mr Shit" is not. Mirrors DisplayName.validate.
create or replace function private.valid_name(p_name text) returns text
language plpgsql stable security definer set search_path = public as $$
declare
  v text;
  v_lower text;
  v_words text;
begin
  if p_name is null then raise exception 'invalid_name'; end if;
  v := btrim(regexp_replace(normalize(p_name, NFKC), '\s+', ' ', 'g'));
  if char_length(v) not between 2 and 24
     or v ~ '[[:cntrl:]<>@/\\:]'
     or v ~* '(https?|www\.)' then
    raise exception 'invalid_name';
  end if;
  v_lower := lower(v);
  v_words := ' ' || btrim(regexp_replace(v_lower, '[^a-z0-9]+', ' ', 'g')) || ' ';
  if exists (select 1 from blocked_words w
             where case when w.whole_word then position(' ' || w.word || ' ' in v_words) > 0
                        else position(w.word in v_lower) > 0 end) then
    raise exception 'invalid_name';
  end if;
  return v;
end $$;

-- 8 characters from ABCDEFGHJKLMNPQRSTUVWXYZ23456789 (32 symbols, so byte % 32 is unbiased).
create or replace function private.new_code() returns text
language plpgsql volatile security definer set search_path = public as $$
declare
  v_bytes bytea := extensions.gen_random_bytes(8);
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_out text := '';
begin
  for i in 0..7 loop
    v_out := v_out || substr(v_alphabet, (get_byte(v_bytes, i) % 32) + 1, 1);
  end loop;
  return v_out;
end $$;

-- An invite code as typed: strip everything but letters and digits, upper-case.
create or replace function private.normalize_code(p_code text) returns text
language sql immutable as $$
  select upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'))
$$;

-- Scores for one competition, live (SQL is authoritative; Swift FriendsScoring mirrors it in exact integer arithmetic,
-- so an exact half point rounds up on both sides). n = window days; a missing day counts 0. Joined and left members are scored; only joined members who still share the metric (at either level)
-- are ranked. Places use rank(), so ties share a place (1, 1, 3).
create or replace function private.competition_scores(p_id uuid)
returns table(user_id uuid, state text, score int, place int, days_counted int, capped_days int, sharing boolean,
              source_mix text)
language sql stable security definer set search_path = public as $$
  with c as (
    select * from competitions where id = p_id
  ), win as (
    select d::date as day from c, generate_series(c.start_day::timestamp, c.end_day::timestamp, interval '1 day') as d
  ), n as (
    select count(*)::numeric as days from win
  ), mem as (
    select m.user_id, m.state, m.locked_goal,
           exists (select 1 from share_settings s, c where s.user_id = m.user_id and s.metric = c.metric) as sharing
    from competition_members m
    where m.competition_id = p_id and m.state in ('joined','left')
  ), vals as (
    select mem.user_id, w.day, coalesce(d.value, 0) as v, coalesce(d.capped, false) as capped, d.source,
           (d.user_id is not null) as has_row
    from mem
    cross join win w
    left join daily_values d on d.user_id = mem.user_id and d.day = w.day and d.metric = (select metric from c)
  ), agg as (
    select mem.user_id, mem.state, mem.sharing,
           case
             when not mem.sharing then null
             when c.mode = 'goal_percent' and c.metric = 'steps' then
               sum(round(least(vals.v::numeric / greatest(mem.locked_goal, 1), 2.0) * 100))
             -- One division of exact integers (Σv × 7 over goal × days), never through goal × days / 7.0: that
             -- divisor is a repeating decimal numeric must cut short, which can tip an exact .5 either way.
             when c.mode = 'goal_percent' then
               round(least(sum(vals.v)::numeric * 7 / (greatest(mem.locked_goal, 1) * (select days from n)), 2.0) * 100)
             when c.mode = 'days_at_goal' then
               count(*) filter (where vals.v >= coalesce(mem.locked_goal, 2147483647))
             else sum(vals.v)
           end::int as score,
           case when mem.sharing then count(*) filter (where vals.has_row) else 0 end::int as days_counted,
           case when mem.sharing then count(*) filter (where vals.capped) else 0 end::int as capped_days,
           string_agg(distinct vals.source, '+' order by vals.source) as source_mix
    from mem
    cross join c
    join vals on vals.user_id = mem.user_id
    group by mem.user_id, mem.state, mem.sharing, mem.locked_goal, c.mode, c.metric
  )
  select agg.user_id, agg.state, agg.score,
         case when agg.state = 'joined' and agg.score is not null
              then (rank() over (partition by (agg.state = 'joined' and agg.score is not null) order by agg.score desc))::int
         end as place,
         agg.days_counted, agg.capped_days, agg.sharing, agg.source_mix
  from agg
$$;

-- Freezes the results once, under a row lock, after freeze_at. Called lazily by competition_standings and by cron.
create or replace function private.finalize_competition(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_comp competitions%rowtype;
begin
  select * into v_comp from competitions where id = p_id for update;
  if not found or v_comp.finalized_at is not null or now() < v_comp.freeze_at then return; end if;
  insert into competition_results(competition_id, user_id, score, place, days_counted, capped_days)
  select p_id, s.user_id, s.score, s.place, s.days_counted, s.capped_days
  from private.competition_scores(p_id) s
  on conflict (competition_id, user_id) do nothing;
  update competitions set finalized_at = now() where id = p_id;
end $$;

-- Retention (§3.6), daily at 03:17 UTC.
create or replace function private.purge_retention() returns void
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  for v_id in select id from competitions where freeze_at <= now() and finalized_at is null loop
    perform private.finalize_competition(v_id);
  end loop;
  delete from daily_values where day < current_date - 35;
  delete from trend_values where week_start < current_date - 35;
  delete from invites      where expires_at < now() - interval '1 day';
  delete from competitions where end_day < current_date - 90;            -- members and results cascade
  delete from reports      where created_at < now() - interval '12 months';
  delete from rate_limits  where window_start < now() - interval '2 days';
  -- GDPR storage limitation: accounts unused for 13 months are deleted (cascades every row).
  delete from auth.users u using profiles p where p.id = u.id and p.last_seen_at < now() - interval '13 months';
  -- Sign-ins that never made a profile (Sign in with Apple, then "Not now" or nothing at the name step) hold
  -- only the Apple identity; nothing ever ages them out otherwise, so they go after 7 days.
  delete from auth.users u
   where not exists (select 1 from profiles p where p.id = u.id)
     and u.created_at < now() - interval '7 days';
end $$;

-- One competition as my_competitions and competition_standings return it.
create or replace function private.competition_json(p_id uuid, p_viewer uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', c.id, 'metric', c.metric, 'mode', c.mode, 'start_day', c.start_day, 'end_day', c.end_day,
    'created_by', c.created_by, 'freeze_at', c.freeze_at, 'finalized', c.finalized_at is not null,
    'my_state', (select m.state from competition_members m where m.competition_id = c.id and m.user_id = p_viewer),
    'members', coalesce((
      select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'display_name', p.display_name, 'state', m.state)
                       order by p.display_name)
      from competition_members m join profiles p on p.id = m.user_id
      where m.competition_id = c.id and m.state in ('invited','joined','left')
        and not exists (select 1 from blocks b
                        where (b.blocker = p_viewer and b.blocked = m.user_id)
                           or (b.blocker = m.user_id and b.blocked = p_viewer))), '[]'::jsonb))
  from competitions c where c.id = p_id
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. RPCs (the API). Each begins with require_profile() (except complete_profile / delete_account) and a rate check.
-- ---------------------------------------------------------------------------------------------------------------------

-- Creates or renames the caller's profile. 16+ is a self-declaration, stored as a timestamp.
create or replace function public.complete_profile(p_display_name text, p_age_confirmed boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_name text;
  v_row profiles%rowtype;
begin
  if v_me is null then raise exception 'not_signed_in'; end if;
  if not coalesce(p_age_confirmed, false) then raise exception 'age_required'; end if;
  v_name := private.valid_name(p_display_name);
  insert into profiles(id, display_name, age_confirmed_at)
  values (v_me, v_name, now())
  on conflict (id) do update set display_name = excluded.display_name, last_seen_at = now()
  returning * into v_row;
  perform private.bump_rate('complete_profile', 10, interval '1 hour');
  return jsonb_build_object('id', v_row.id, 'display_name', v_row.display_name,
                            'step_goal', v_row.step_goal, 'intensity_goal', v_row.intensity_goal);
end $$;

create or replace function public.update_profile(p_display_name text default null, p_step_goal int default null,
                                                 p_intensity_goal int default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := private.require_profile();
begin
  perform private.bump_rate('update_profile', 60, interval '1 hour');
  update profiles set
    display_name   = case when p_display_name is null then display_name else private.valid_name(p_display_name) end,
    step_goal      = case when p_step_goal is null then step_goal else least(greatest(p_step_goal, 3000), 30000) end,
    intensity_goal = case when p_intensity_goal is null then intensity_goal
                          else least(greatest(p_intensity_goal, 60), 600) end
  where id = v_me;
end $$;

-- One metric's sharing level. p_audience null = Off: deletes the share row AND every row of that metric, in this
-- transaction (Art. 7(3)). Every call is appended to consent_log.
create or replace function public.set_share(p_metric text, p_audience text, p_consent_version int) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := private.require_profile();
begin
  perform private.bump_rate('set_share', 60, interval '1 hour');
  if p_metric is null or p_metric not in ('steps','intensity','active','sleep_goal','bedtime','hrv','rhr','readiness') then
    raise exception 'invalid_audience';
  end if;
  if p_audience is not null and p_audience not in ('competitions','friends') then raise exception 'invalid_audience'; end if;
  if p_metric in ('hrv','rhr','readiness') and p_audience = 'competitions' then raise exception 'invalid_audience'; end if;
  if coalesce(p_consent_version, 0) < 1 then raise exception 'invalid_audience'; end if;

  if p_audience is null then
    delete from share_settings where user_id = v_me and metric = p_metric;
    delete from daily_values   where user_id = v_me and metric = p_metric;
    delete from trend_values   where user_id = v_me and metric = p_metric;
  else
    insert into share_settings(user_id, metric, audience, consent_version)
    values (v_me, p_metric, p_audience, p_consent_version)
    on conflict (user_id, metric) do update
      set audience = excluded.audience, consent_version = excluded.consent_version, granted_at = now();
  end if;
  insert into consent_log(user_id, metric, audience, version) values (v_me, p_metric, p_audience, p_consent_version);
end $$;

-- The caller's derived rows. Unshared metrics and out-of-window rows are dropped; values over a cap are clamped and
-- flagged; rows are upserted. A row whose value is null RETRACTS that day: the phone no longer has a shareable value
-- for it (phone steps deleted from Apple Health, a night edited away), so the stored row is deleted rather than left
-- counting in friends' boards and competitions. Also prunes the caller's own expired rows, so retention holds without
-- pg_cron.
create or replace function public.upload(p_days jsonb, p_trends jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := private.require_profile();
  v_days jsonb := coalesce(p_days, '[]'::jsonb);
  v_trends jsonb := coalesce(p_trends, '[]'::jsonb);
  v_accepted int := 0;
  v_dropped int := 0;
  r record;
  v_value int;
  v_capped boolean;
  v_cap int;
  v_delta int;
  v_clip int;
begin
  perform private.bump_rate('upload', 60, interval '1 hour');
  if jsonb_typeof(v_days) <> 'array' or jsonb_typeof(v_trends) <> 'array'
     or jsonb_array_length(v_days) > 175 or jsonb_array_length(v_trends) > 15 then
    raise exception 'invalid_window';
  end if;

  for r in select * from jsonb_to_recordset(v_days) as x(day date, metric text, value int, source text, capped boolean) loop
    if r.metric is null or r.metric not in ('steps','intensity','active','sleep_goal','bedtime')
       or r.day is null or r.day < current_date - 36 or r.day > current_date + 1 then
      v_dropped := v_dropped + 1;
      continue;
    end if;
    if r.value is null then   -- a retraction: the caller's own row only, shared or not
      delete from daily_values where user_id = v_me and metric = r.metric and day = r.day;
      v_accepted := v_accepted + 1;
      continue;
    end if;
    if r.value < 0
       or not exists (select 1 from share_settings s where s.user_id = v_me and s.metric = r.metric)
       or (r.metric = 'steps' and coalesce(r.source, '') not in ('strap','phone')) then
      v_dropped := v_dropped + 1;
      continue;
    end if;
    v_cap := case r.metric when 'steps' then 60000 when 'intensity' then 300 else 1 end;
    v_capped := r.metric in ('steps','intensity') and (r.value > v_cap or coalesce(r.capped, false));
    v_value := least(r.value, v_cap);
    insert into daily_values(user_id, day, metric, value, source, capped, updated_at)
    values (v_me, r.day, r.metric, v_value, case when r.metric = 'steps' then r.source end, v_capped, now())
    on conflict (user_id, metric, day) do update
      set value = excluded.value, source = excluded.source, capped = excluded.capped, updated_at = now();
    v_accepted := v_accepted + 1;
  end loop;

  for r in select * from jsonb_to_recordset(v_trends)
             as x(metric text, week_start date, status text, delta int, band text, clipped boolean) loop
    if r.metric is null or r.metric not in ('hrv','rhr','readiness')
       or r.week_start is null or extract(isodow from r.week_start) <> 1
       or r.week_start < current_date - 42 or r.week_start > current_date + 1
       or r.status is null or r.status not in ('calibrating','ready')
       or not exists (select 1 from share_settings s where s.user_id = v_me and s.metric = r.metric)
       or (r.status = 'ready' and (r.delta is null or r.band is null or r.band not in ('below','within','above'))) then
      v_dropped := v_dropped + 1;
      continue;
    end if;
    v_clip := case r.metric when 'hrv' then 30 when 'rhr' then 10 else 15 end;
    v_delta := case when r.status = 'ready' then least(greatest(r.delta, -v_clip), v_clip) end;
    insert into trend_values(user_id, metric, week_start, status, delta, band, clipped, updated_at)
    values (v_me, r.metric, r.week_start, r.status, v_delta,
            case when r.status = 'ready' then r.band end,
            r.status = 'ready' and (coalesce(r.clipped, false) or abs(r.delta) > v_clip), now())
    on conflict (user_id, metric, week_start) do update
      set status = excluded.status, delta = excluded.delta, band = excluded.band, clipped = excluded.clipped,
          updated_at = now();
    v_accepted := v_accepted + 1;
  end loop;

  delete from daily_values where user_id = v_me and day < current_date - 35;
  delete from trend_values where user_id = v_me and week_start < current_date - 35;
  return jsonb_build_object('accepted', v_accepted, 'dropped', v_dropped);
end $$;

-- Everything the server holds about the caller (Art. 15/20).
create or replace function public.my_data() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := private.require_profile();
begin
  perform private.bump_rate('my_data', 10, interval '1 hour');
  return jsonb_build_object(
    'profile', (select to_jsonb(p) from profiles p where p.id = v_me),
    'shares', coalesce((select jsonb_agg(to_jsonb(s)) from share_settings s where s.user_id = v_me), '[]'::jsonb),
    'consent_log', coalesce((select jsonb_agg(to_jsonb(l) order by l.at) from consent_log l where l.user_id = v_me), '[]'::jsonb),
    'daily_values', coalesce((select jsonb_agg(to_jsonb(d) order by d.day, d.metric) from daily_values d where d.user_id = v_me), '[]'::jsonb),
    'trend_values', coalesce((select jsonb_agg(to_jsonb(t) order by t.week_start, t.metric) from trend_values t where t.user_id = v_me), '[]'::jsonb),
    'friendships', coalesce((
      select jsonb_agg(jsonb_build_object('friend_id', p.id, 'display_name', p.display_name, 'status', f.status,
                                          'requested_by_me', f.requested_by = v_me, 'created_at', f.created_at))
      from friendships f join profiles p on p.id = case when f.user_a = v_me then f.user_b else f.user_a end
      where v_me in (f.user_a, f.user_b)), '[]'::jsonb),
    'hidden_from', coalesce((select jsonb_agg(h.viewer) from friend_hides h where h.owner = v_me), '[]'::jsonb),
    'blocked', coalesce((select jsonb_agg(b.blocked) from blocks b where b.blocker = v_me), '[]'::jsonb),
    'invites', coalesce((select jsonb_agg(to_jsonb(i)) from invites i where i.created_by = v_me), '[]'::jsonb),
    'competitions_created', coalesce((select jsonb_agg(to_jsonb(c)) from competitions c where c.created_by = v_me), '[]'::jsonb),
    'memberships', coalesce((select jsonb_agg(to_jsonb(m)) from competition_members m where m.user_id = v_me), '[]'::jsonb),
    'results', coalesce((select jsonb_agg(to_jsonb(r)) from competition_results r where r.user_id = v_me), '[]'::jsonb),
    'reports_made', coalesce((select jsonb_agg(jsonb_build_object('reported', r.reported, 'reason', r.reason, 'created_at', r.created_at))
                              from reports r where r.reporter = v_me), '[]'::jsonb));
end $$;

-- A single-use code, valid 7 days. At most 5 open per person.
create or replace function public.create_invite() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := private.require_profile();
  v_code text;
  v_expires timestamptz;
begin
  perform private.bump_rate('create_invite', 10, interval '1 day');
  if (select count(*) from invites where created_by = v_me and used_by is null and expires_at > now()) >= 5 then
    raise exception 'invite_limit';
  end if;
  loop
    v_code := private.new_code();
    insert into invites(code, created_by) values (v_code, v_me) on conflict (code) do nothing
    returning expires_at into v_expires;
    exit when v_expires is not null;
  end loop;
  return jsonb_build_object('code', v_code, 'expires_at', v_expires);
end $$;

-- Who a code belongs to, changing nothing ("Connect with Sam?"). Same checks as redeem_invite.
-- A refused code RETURNS {"error": key} instead of raising: a raise would roll back this call's bump_rate, so wrong
-- guesses would never count and the 30-an-hour limit would only ever see codes that worked. The client maps the key
-- exactly like a raised one (FriendsJSON.throwIfError).
create or replace function public.peek_invite(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := private.require_profile();
  v_code text := private.normalize_code(p_code);
  v_inv invites%rowtype;
begin
  perform private.bump_rate('peek_invite', 30, interval '1 hour');
  if v_code !~ '^[A-HJ-NP-Z2-9]{8}$' then return jsonb_build_object('error', 'invite_invalid'); end if;
  select * into v_inv from invites where code = v_code;
  if not found then return jsonb_build_object('error', 'invite_invalid'); end if;
  if v_inv.created_by = v_me then return jsonb_build_object('error', 'invite_self'); end if;
  if v_inv.used_by is not null then return jsonb_build_object('error', 'invite_used'); end if;
  if v_inv.expires_at < now() then return jsonb_build_object('error', 'invite_expired'); end if;
  if private.is_blocked_between(v_inv.created_by) then return jsonb_build_object('error', 'blocked'); end if;
  if exists (select 1 from friendships where user_a = least(v_me, v_inv.created_by) and user_b = greatest(v_me, v_inv.created_by)) then
    return jsonb_build_object('error', 'already_friends');
  end if;
  return jsonb_build_object('display_name', (select display_name from profiles where id = v_inv.created_by),
                            'expires_at', v_inv.expires_at);
end $$;

-- Uses a code: creates a PENDING request that the code's owner accepts (respond_friend). Refusals are returned as
-- {"error": key}, not raised, for the same reason as peek_invite: so the 10-an-hour limit counts wrong guesses.
create or replace function public.redeem_invite(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := private.require_profile();
  v_code text := private.normalize_code(p_code);
  v_inv invites%rowtype;
begin
  perform private.bump_rate('redeem_invite', 10, interval '1 hour');
  if v_code !~ '^[A-HJ-NP-Z2-9]{8}$' then return jsonb_build_object('error', 'invite_invalid'); end if;
  select * into v_inv from invites where code = v_code for update;
  if not found then return jsonb_build_object('error', 'invite_invalid'); end if;
  if v_inv.created_by = v_me then return jsonb_build_object('error', 'invite_self'); end if;
  if v_inv.used_by is not null then return jsonb_build_object('error', 'invite_used'); end if;
  if v_inv.expires_at < now() then return jsonb_build_object('error', 'invite_expired'); end if;
  if private.is_blocked_between(v_inv.created_by) then return jsonb_build_object('error', 'blocked'); end if;
  if exists (select 1 from friendships where user_a = least(v_me, v_inv.created_by) and user_b = greatest(v_me, v_inv.created_by)) then
    return jsonb_build_object('error', 'already_friends');
  end if;
  if (select count(*) from friendships where v_me in (user_a, user_b)) >= 50
     or (select count(*) from friendships where v_inv.created_by in (user_a, user_b)) >= 50 then
    return jsonb_build_object('error', 'friend_limit');
  end if;
  insert into friendships(user_a, user_b, requested_by, status)
  values (least(v_me, v_inv.created_by), greatest(v_me, v_inv.created_by), v_me, 'pending');
  update invites set used_by = v_me, used_at = now() where code = v_code;
  return jsonb_build_object('friend_id', v_inv.created_by,
                            'display_name', (select display_name from profiles where id = v_inv.created_by));
end $$;

-- Only the person who did NOT send the request answers it. Decline deletes the row.
create or replace function public.respond_friend(p_other uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := private.require_profile();
begin
  perform private.bump_rate('respond_friend', 60, interval '1 hour');
  if not exists (select 1 from friendships
                 where user_a = least(v_me, p_other) and user_b = greatest(v_me, p_other)
                   and status = 'pending' and requested_by = p_other) then
    raise exception 'not_found';
  end if;
  if coalesce(p_accept, false) then
    update friendships set status = 'accepted', accepted_at = now()
    where user_a = least(v_me, p_other) and user_b = greatest(v_me, p_other);
  else
    delete from friendships where user_a = least(v_me, p_other) and user_b = greatest(v_me, p_other);
  end if;
end $$;

-- "Hide my data from <friend>": invisible to the friend (only the owner can read friend_hides).
create or replace function public.set_hidden(p_other uuid, p_hidden boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := private.require_profile();
begin
  perform private.bump_rate('set_hidden', 60, interval '1 hour');
  if not exists (select 1 from friendships where user_a = least(v_me, p_other) and user_b = greatest(v_me, p_other)) then
    raise exception 'not_friends';
  end if;
  if coalesce(p_hidden, false) then
    insert into friend_hides(owner, viewer) values (v_me, p_other) on conflict do nothing;
  else
    delete from friend_hides where owner = v_me and viewer = p_other;
  end if;
end $$;

create or replace function public.remove_friend(p_other uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := private.require_profile();
begin
  perform private.bump_rate('remove_friend', 60, interval '1 hour');
  delete from friendships where user_a = least(v_me, p_other) and user_b = greatest(v_me, p_other);
  delete from friend_hides where owner = v_me and viewer = p_other;
end $$;

-- Blocks both ways for visibility; removes the friendship and hides; removes the blocked person from competitions the
-- caller created that have not ended.
create or replace function public.block_user(p_other uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := private.require_profile();
begin
  perform private.bump_rate('block_user', 30, interval '1 day');
  if p_other is null or p_other = v_me or not exists (select 1 from profiles where id = p_other) then
    raise exception 'not_found';
  end if;
  insert into blocks(blocker, blocked) values (v_me, p_other) on conflict do nothing;
  delete from friendships where user_a = least(v_me, p_other) and user_b = greatest(v_me, p_other);
  delete from friend_hides where (owner = v_me and viewer = p_other) or (owner = p_other and viewer = v_me);
  update competition_members m set state = 'removed', responded_at = now()
  from competitions c
  where c.id = m.competition_id and c.created_by = v_me and c.end_day >= current_date
    and m.user_id = p_other and m.state in ('invited','joined');
end $$;

create or replace function public.unblock_user(p_other uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := private.require_profile();
begin
  perform private.bump_rate('unblock_user', 30, interval '1 day');
  delete from blocks where blocker = v_me and blocked = p_other;
end $$;

-- Fixed reasons, no free text. The caller must know the person (or have blocked them).
create or replace function public.report_user(p_other uuid, p_reason text, p_competition uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := private.require_profile();
begin
  perform private.bump_rate('report_user', 20, interval '1 day');
  if p_reason is null or p_reason not in ('name','cheating','harassment','other') then raise exception 'not_found'; end if;
  if not (private.knows(p_other) or exists (select 1 from blocks where blocker = v_me and blocked = p_other)) then
    raise exception 'not_found';
  end if;
  if p_competition is not null and not private.is_competition_member(p_competition) then
    p_competition := null;
  end if;
  insert into reports(reporter, reported, reason, competition_id) values (v_me, p_other, p_reason, p_competition);
end $$;

-- The Friends tab in one call. SECURITY INVOKER: RLS (can_see, knows) decides every row, so a hidden, blocked,
-- unshared or competitions-only row can never appear here. One scalar jsonb, so PostgREST's row cap doesn't apply.
create or replace function public.friends_overview(p_from date, p_to date) returns jsonb
language plpgsql volatile security invoker set search_path = public as $$
declare
  v_me uuid := private.require_profile();
begin
  perform private.bump_rate('friends_overview', 240, interval '1 hour');
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 34 then raise exception 'invalid_window'; end if;
  return jsonb_build_object(
    'me', (select jsonb_build_object('id', p.id, 'display_name', p.display_name, 'step_goal', p.step_goal,
                                     'intensity_goal', p.intensity_goal)
           from profiles p where p.id = v_me),
    'my_shares', coalesce((select jsonb_agg(jsonb_build_object('metric', s.metric, 'audience', s.audience))
                           from share_settings s where s.user_id = v_me), '[]'::jsonb),
    'hides', coalesce((select jsonb_agg(h.viewer) from friend_hides h where h.owner = v_me), '[]'::jsonb),
    'friends', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'display_name', p.display_name, 'step_goal', p.step_goal,
                                          'intensity_goal', p.intensity_goal, 'status', f.status,
                                          'requested_by_me', f.requested_by = v_me))
      from friendships f
      join profiles p on p.id = case when f.user_a = v_me then f.user_b else f.user_a end
      where v_me in (f.user_a, f.user_b)), '[]'::jsonb),
    'days', coalesce((
      select jsonb_agg(jsonb_build_object('user_id', d.user_id, 'day', d.day, 'metric', d.metric, 'value', d.value,
                                          'source', d.source, 'capped', d.capped) order by d.user_id, d.day, d.metric)
      from daily_values d where d.day between p_from and p_to), '[]'::jsonb),
    'trends', coalesce((
      select jsonb_agg(jsonb_build_object('user_id', t.user_id, 'metric', t.metric, 'week_start', t.week_start,
                                          'status', t.status, 'delta', t.delta, 'band', t.band, 'clipped', t.clipped)
                       order by t.user_id, t.week_start, t.metric)
      from trend_values t where t.week_start >= p_to - 42), '[]'::jsonb));
end $$;

-- Every competition the caller is (or was) in, finished ones from the last 90 days. SECURITY INVOKER: RLS
-- (private.is_competition_member) decides which; member names come through private.competition_json, which drops
-- blocked people.
create or replace function public.my_competitions() returns jsonb
language plpgsql volatile security invoker set search_path = public as $$
declare
  v_me uuid := private.require_profile();
begin
  perform private.bump_rate('my_competitions', 240, interval '1 hour');
  return coalesce((
    select jsonb_agg(private.competition_json(c.id, v_me) order by c.start_day desc, c.id)
    from competitions c where c.end_day >= current_date - 90), '[]'::jsonb);
end $$;

create or replace function public.create_competition(p_metric text, p_mode text, p_start date, p_end date,
                                                     p_invitees uuid[]) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := private.require_profile();
  v_invitees uuid[];
  v_id uuid;
  v_goal int;
  v_uid uuid;
begin
  perform private.bump_rate('create_competition', 10, interval '1 day');
  select coalesce(array_agg(distinct x), '{}') into v_invitees from unnest(coalesce(p_invitees, '{}')) as x where x <> v_me;
  if cardinality(v_invitees) < 1 or cardinality(v_invitees) > 9 then raise exception 'too_many_participants'; end if;
  foreach v_uid in array v_invitees loop
    if not private.are_friends(v_uid) or private.is_blocked_between(v_uid) then raise exception 'not_friends'; end if;
  end loop;
  if p_start is null or p_end is null or p_end < p_start or p_end - p_start > 30
     or p_start < current_date - 1 or p_start > current_date + 30 then
    raise exception 'invalid_window';
  end if;
  if p_metric is null or p_mode is null or not (case p_metric
        when 'steps'      then p_mode in ('goal_percent','total','days_at_goal')
        when 'intensity'  then p_mode in ('goal_percent','total')
        when 'active'     then p_mode = 'total'
        when 'sleep_goal' then p_mode = 'total'
        when 'bedtime'    then p_mode = 'total'
        else false end) then
    raise exception 'invalid_mode';
  end if;
  if not exists (select 1 from share_settings where user_id = v_me and metric = p_metric) then
    raise exception 'metric_not_shared';
  end if;
  select case p_metric when 'steps' then step_goal when 'intensity' then intensity_goal end into v_goal
  from profiles where id = v_me;
  insert into competitions(created_by, metric, mode, start_day, end_day, freeze_at)
  values (v_me, p_metric, p_mode, p_start, p_end, ((p_end + 3)::timestamp + interval '12 hours') at time zone 'UTC')
  returning id into v_id;
  insert into competition_members(competition_id, user_id, state, locked_goal, responded_at)
  values (v_id, v_me, 'joined', v_goal, now());
  insert into competition_members(competition_id, user_id, state)
  select v_id, x, 'invited' from unnest(v_invitees) as x;
  return v_id;
end $$;

-- Join or decline an invitation. Joining closes the day after the start, needs the metric shared at either level, and
-- locks the joiner's goal. A late joiner is scored over the full window (missing days count 0).
create or replace function public.respond_competition(p_id uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := private.require_profile();
  v_comp competitions%rowtype;
  v_goal int;
begin
  perform private.bump_rate('respond_competition', 60, interval '1 hour');
  select * into v_comp from competitions where id = p_id;
  if not found or not exists (select 1 from competition_members
                              where competition_id = p_id and user_id = v_me and state = 'invited') then
    raise exception 'not_found';
  end if;
  if coalesce(p_accept, false) then
    if current_date > v_comp.start_day + 1 then raise exception 'joining_closed'; end if;
    if not exists (select 1 from share_settings where user_id = v_me and metric = v_comp.metric) then
      raise exception 'metric_not_shared';
    end if;
    select case v_comp.metric when 'steps' then step_goal when 'intensity' then intensity_goal end into v_goal
    from profiles where id = v_me;
    update competition_members set state = 'joined', locked_goal = v_goal, responded_at = now()
    where competition_id = p_id and user_id = v_me;
  else
    update competition_members set state = 'declined', responded_at = now()
    where competition_id = p_id and user_id = v_me;
  end if;
end $$;

-- Leaving keeps the score visible as "Left", unranked.
create or replace function public.leave_competition(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := private.require_profile();
begin
  perform private.bump_rate('leave_competition', 60, interval '1 hour');
  update competition_members set state = 'left', responded_at = now()
  where competition_id = p_id and user_id = v_me and state = 'joined';
  if not found then raise exception 'not_member'; end if;
end $$;

create or replace function public.remove_participant(p_id uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := private.require_profile();
begin
  perform private.bump_rate('remove_participant', 60, interval '1 hour');
  if not exists (select 1 from competitions where id = p_id) then raise exception 'not_found'; end if;
  if not exists (select 1 from competitions where id = p_id and created_by = v_me) then raise exception 'not_creator'; end if;
  if p_user = v_me then raise exception 'not_found'; end if;
  update competition_members set state = 'removed', responded_at = now()
  where competition_id = p_id and user_id = p_user and state in ('invited','joined','left');
  if not found then raise exception 'not_found'; end if;
end $$;

-- The standings. SECURITY DEFINER, and therefore the trust boundary for "Only in competitions" sharing: those rows are
-- invisible in daily_values to everyone but their owner, and reach co-competitors only as scores here. Members only;
-- blocked people are filtered out for this viewer; my_days holds the caller's own days alone. Finalises lazily, once.
-- Scores go only to people taking part ("only inside competitions you join"): a joined member while it runs, and
-- anyone who joined once it is final. An invited person (who may share nothing back) gets the roster in
-- 'competition' and no rows until they join; someone who left stops following the live totals.
create or replace function public.competition_standings(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := private.require_profile();
  v_comp competitions%rowtype;
  v_my_state text;
  v_rows jsonb := '[]'::jsonb;
  v_my_days jsonb := '[]'::jsonb;
begin
  perform private.bump_rate('competition_standings', 600, interval '1 hour');
  if not private.is_competition_member(p_id) then raise exception 'not_member'; end if;
  perform private.finalize_competition(p_id);
  select * into v_comp from competitions where id = p_id;
  select m.state into v_my_state from competition_members m where m.competition_id = p_id and m.user_id = v_me;

  -- Invited, or left while it runs: no scores, v_rows stays empty.
  if v_my_state <> 'joined' and not (v_comp.finalized_at is not null and v_my_state = 'left') then
    v_rows := '[]'::jsonb;
  elsif v_comp.finalized_at is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
             'user_id', r.user_id, 'display_name', p.display_name, 'state', m.state, 'score', r.score, 'place', r.place,
             'days_counted', r.days_counted, 'capped_days', r.capped_days, 'sharing', r.score is not null,
             'source_mix', null) order by r.place nulls last, p.display_name), '[]'::jsonb)
      into v_rows
    from competition_results r
    join profiles p on p.id = r.user_id
    join competition_members m on m.competition_id = r.competition_id and m.user_id = r.user_id
    where r.competition_id = p_id and m.state in ('joined','left')
      and not exists (select 1 from blocks b where (b.blocker = v_me and b.blocked = r.user_id)
                                              or (b.blocker = r.user_id and b.blocked = v_me));
  else
    select coalesce(jsonb_agg(jsonb_build_object(
             'user_id', s.user_id, 'display_name', p.display_name, 'state', s.state, 'score', s.score, 'place', s.place,
             'days_counted', s.days_counted, 'capped_days', s.capped_days, 'sharing', s.sharing,
             'source_mix', s.source_mix) order by s.place nulls last, p.display_name), '[]'::jsonb)
      into v_rows
    from private.competition_scores(p_id) s
    join profiles p on p.id = s.user_id
    where not exists (select 1 from blocks b where (b.blocker = v_me and b.blocked = s.user_id)
                                              or (b.blocker = s.user_id and b.blocked = v_me));
  end if;

  -- The caller's own days, once they have a locked goal to score them against (never while only invited).
  if v_my_state in ('joined','left') then
    select coalesce(jsonb_agg(jsonb_build_object(
             'day', w.day, 'value', coalesce(d.value, 0),
             'points', case
                         when v_comp.mode = 'goal_percent' and v_comp.metric = 'steps' then
                           round(least(coalesce(d.value, 0)::numeric / greatest(m.locked_goal, 1), 2.0) * 100)::int
                         when v_comp.mode = 'days_at_goal' then
                           case when coalesce(d.value, 0) >= coalesce(m.locked_goal, 2147483647) then 1 else 0 end
                         else coalesce(d.value, 0) end,
             'capped', coalesce(d.capped, false)) order by w.day), '[]'::jsonb)
      into v_my_days
    from (select g::date as day
          from generate_series(v_comp.start_day::timestamp, least(v_comp.end_day, current_date + 1)::timestamp,
                               interval '1 day') as g) as w
    join competition_members m on m.competition_id = p_id and m.user_id = v_me
    left join daily_values d on d.user_id = v_me and d.metric = v_comp.metric and d.day = w.day;
  end if;

  return jsonb_build_object('competition', private.competition_json(p_id, v_me),
                            'final', v_comp.finalized_at is not null,
                            'freeze_at', v_comp.freeze_at,
                            'rows', v_rows,
                            'my_days', v_my_days);
end $$;

-- Account deletion without the Edge Function (the app's fallback): deletes the auth user, which cascades every row.
create or replace function public.delete_account() returns void
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not_signed_in'; end if;
  if exists (select 1 from profiles where id = v_me) then
    perform private.bump_rate('delete_account', 5, interval '1 hour');
  end if;
  delete from auth.users where id = v_me;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Seed: blocked words (lower case; keep identical, order included, to DisplayName.blockedSubstrings (false) and
--    DisplayName.blockedWholeWords (true) in Baseline/Friends/FriendsModels.swift). The seed is the whole list: a word
--    no longer in it is deleted, so re-running the file also retires entries ("isis" and "heil" are real names).
-- ---------------------------------------------------------------------------------------------------------------------
with seed(word, whole_word) as (values
  ('admin', false), ('administrator', false), ('moderator', false), ('official', false), ('baseline team', false),
  ('baselineteam', false), ('support team', false), ('anthropic', false), ('apple support', false),
  ('whoop support', false), ('customer service', false),
  ('fuck', false), ('fucker', false), ('fucking', false), ('motherfucker', false), ('bullshit', false),
  ('asshole', false), ('bitch', false), ('cunt', false), ('dickhead', false), ('wanker', false), ('bollocks', false),
  ('whore', false), ('pornhub', false), ('onlyfans', false), ('xxx', false), ('blowjob', false), ('handjob', false),
  ('dildo', false), ('pussy', false), ('vagina', false), ('boobs', false), ('nipple', false), ('orgasm', false),
  ('hitler', false), ('kkk', false), ('pedophile', false), ('retard', false), ('faggot', false), ('nigger', false),
  ('nigga', false), ('killyourself', false),
  ('shit', true), ('bastard', true), ('twat', true), ('prick', true), ('slut', true), ('porn', true), ('porno', true),
  ('cock', true), ('penis', true), ('tits', true), ('horny', true), ('nazi', true), ('rapist', true), ('pedo', true),
  ('paedo', true), ('kys', true)
), retired as (
  delete from public.blocked_words b where not exists (select 1 from seed s where s.word = b.word)
)
insert into public.blocked_words(word, whole_word) select word, whole_word from seed
on conflict (word) do update set whole_word = excluded.whole_word;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. Retention job (requires pg_cron; re-running replaces the job of the same name)
-- ---------------------------------------------------------------------------------------------------------------------
select cron.schedule('baseline-retention', '17 3 * * *', 'select private.purge_retention()');

-- ---------------------------------------------------------------------------------------------------------------------
-- 7. Policies and grants (after a second blanket revoke)
-- ---------------------------------------------------------------------------------------------------------------------
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on all functions in schema public  from public, anon, authenticated;
revoke execute on all functions in schema private from public, anon, authenticated;

drop policy if exists p_profiles    on public.profiles;
drop policy if exists p_shares      on public.share_settings;
drop policy if exists p_consent     on public.consent_log;
drop policy if exists p_daily       on public.daily_values;
drop policy if exists p_trend       on public.trend_values;
drop policy if exists p_friendships on public.friendships;
drop policy if exists p_hides       on public.friend_hides;
drop policy if exists p_invites     on public.invites;
drop policy if exists p_blocks      on public.blocks;
drop policy if exists p_comps       on public.competitions;
drop policy if exists p_members     on public.competition_members;
drop policy if exists p_results     on public.competition_results;

-- The policy helpers used to live in public, where PostgREST served them as RPCs. With the policies that used them
-- dropped above, the old copies can go (re-running this file on an older project); the new ones are in private.
drop function if exists public.can_see(uuid, text);
drop function if exists public.knows(uuid);
drop function if exists public.are_friends(uuid);
drop function if exists public.is_blocked_between(uuid);
drop function if exists public.is_competition_member(uuid);

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
-- A block hides the other person's membership and result rows too, as competition_standings and competition_json
-- already do; the caller's own rows stay visible. Final results, like the standings, go only to people who took part
-- (joined, or joined then left): someone still only invited when it ended sees the roster, never the scores.
create policy p_members     on public.competition_members for select to authenticated
  using (private.is_competition_member(competition_id) and (user_id = auth.uid() or not private.is_blocked_between(user_id)));
create policy p_results     on public.competition_results for select to authenticated
  using (exists (select 1 from public.competition_members m
                 where m.competition_id = competition_results.competition_id and m.user_id = auth.uid()
                   and m.state in ('joined','left'))
         and (user_id = auth.uid() or not private.is_blocked_between(user_id)));
-- reports, rate_limits, blocked_words: RLS on, no policy, no grant.

-- Column grants hide last_seen_at, age_confirmed_at, created_at and updated_at.
grant usage on schema public to authenticated;
grant select (id, display_name, step_goal, intensity_goal)               on public.profiles     to authenticated;
grant select (user_id, day, metric, value, source, capped)               on public.daily_values to authenticated;
grant select (user_id, metric, week_start, status, delta, band, clipped) on public.trend_values to authenticated;
grant select on public.share_settings, public.consent_log, public.friendships, public.friend_hides, public.invites,
                public.blocks, public.competitions, public.competition_members, public.competition_results
             to authenticated;

-- The private schema is not exposed by PostgREST, so nothing below is reachable as /rest/v1/rpc/….
grant usage on schema private to authenticated;

-- Policy helpers run as the caller inside policy expressions.
grant execute on function private.is_blocked_between(uuid)     to authenticated;
grant execute on function private.are_friends(uuid)            to authenticated;
grant execute on function private.can_see(uuid, text)          to authenticated;
grant execute on function private.knows(uuid)                  to authenticated;
grant execute on function private.is_competition_member(uuid)  to authenticated;

-- The two invoker RPCs call these as the caller.
grant execute on function private.require_profile()                  to authenticated;
grant execute on function private.bump_rate(text, int, interval)     to authenticated;
grant execute on function private.competition_json(uuid, uuid)       to authenticated;

-- The API.
grant execute on function public.complete_profile(text, boolean)                     to authenticated;
grant execute on function public.update_profile(text, int, int)                      to authenticated;
grant execute on function public.set_share(text, text, int)                          to authenticated;
grant execute on function public.upload(jsonb, jsonb)                                to authenticated;
grant execute on function public.my_data()                                           to authenticated;
grant execute on function public.create_invite()                                     to authenticated;
grant execute on function public.peek_invite(text)                                   to authenticated;
grant execute on function public.redeem_invite(text)                                 to authenticated;
grant execute on function public.respond_friend(uuid, boolean)                       to authenticated;
grant execute on function public.set_hidden(uuid, boolean)                           to authenticated;
grant execute on function public.remove_friend(uuid)                                 to authenticated;
grant execute on function public.block_user(uuid)                                    to authenticated;
grant execute on function public.unblock_user(uuid)                                  to authenticated;
grant execute on function public.report_user(uuid, text, uuid)                       to authenticated;
grant execute on function public.friends_overview(date, date)                        to authenticated;
grant execute on function public.my_competitions()                                   to authenticated;
grant execute on function public.create_competition(text, text, date, date, uuid[])  to authenticated;
grant execute on function public.respond_competition(uuid, boolean)                  to authenticated;
grant execute on function public.leave_competition(uuid)                             to authenticated;
grant execute on function public.remove_participant(uuid, uuid)                      to authenticated;
grant execute on function public.competition_standings(uuid)                         to authenticated;
grant execute on function public.delete_account()                                    to authenticated;

-- Final check (the owner eyeballs it). Expected: policies 12, anon_table_grants 0, authenticated_write_grants 0,
-- api_policy_helpers 0 (no policy helper left in the API schema).
select 'policies' as what, count(*) from pg_policies where schemaname = 'public'
union all select 'anon_table_grants', count(*) from information_schema.role_table_grants
  where grantee = 'anon' and table_schema = 'public'
union all select 'authenticated_write_grants', count(*) from information_schema.role_table_grants
  where grantee = 'authenticated' and table_schema = 'public' and privilege_type in ('INSERT','UPDATE','DELETE')
union all select 'api_policy_helpers', count(*) from pg_proc f join pg_namespace n on n.oid = f.pronamespace
  where n.nspname = 'public'
    and f.proname in ('is_blocked_between','are_friends','can_see','knows','is_competition_member');

-- =====================================================================================================================
-- SELFTEST (optional; run once by hand). It reproduces the shared scoring fixture (FriendsScoringTests and
-- tests/scoring.sql) with the same expressions private.competition_scores uses, and raises if any number differs.
-- Select from "do $$" to the final "$$;" and run it. It writes nothing.
-- =====================================================================================================================
-- do $$
-- declare
--   v int;
-- begin
--   -- steps · goal_percent, goal 8000: 12000 → 150, 20000 → 200 (capped at 2×)
--   select round(least(12000::numeric / 8000, 2.0) * 100) into v; if v <> 150 then raise exception 'steps 12000: %', v; end if;
--   select round(least(20000::numeric / 8000, 2.0) * 100) into v; if v <> 200 then raise exception 'steps 20000: %', v; end if;
--   -- 7 days at the cap → 1400
--   select sum(round(least(x::numeric / 8000, 2.0) * 100)) into v from unnest(array[20000,20000,20000,20000,20000,20000,20000]) x;
--   if v <> 1400 then raise exception '7 days at cap: %', v; end if;
--   -- an exact half point rounds up: goal 3000, 435 steps = 14.5 → 15 (Double arithmetic would give 14)
--   select round(least(435::numeric / 3000, 2.0) * 100) into v; if v <> 15 then raise exception 'steps half point: %', v; end if;
--   -- intensity · goal_percent, 3-day window, weekly goal 150 (target 64.29): 70 min → 109
--   select round(least(70::numeric * 7 / (150 * 3), 2.0) * 100) into v; if v <> 109 then raise exception 'intensity: %', v; end if;
--   -- intensity half points: weekly goal 200, 7 days, 201 min = 100.5 → 101; 4 days, 44 min = 38.5 → 39
--   select round(least(201::numeric * 7 / (200 * 7), 2.0) * 100) into v; if v <> 101 then raise exception 'intensity half 7d: %', v; end if;
--   select round(least(44::numeric * 7 / (200 * 4), 2.0) * 100) into v; if v <> 39 then raise exception 'intensity half 4d: %', v; end if;
--   -- goal floor: a 2,000 goal is stored as 3,000
--   select least(greatest(2000, 3000), 30000) into v; if v <> 3000 then raise exception 'goal floor: %', v; end if;
--   -- days_at_goal, goal 8000: [9000, 7999, 8000, 0] → 2
--   select count(*) filter (where x >= 8000) into v from unnest(array[9000,7999,8000,0]) x;
--   if v <> 2 then raise exception 'days_at_goal: %', v; end if;
--   -- late joiner, goal 8000, 7-day window, rows only on the last 3 days at 8000 → 300 (missing days count 0)
--   select sum(round(least(coalesce(x, 0)::numeric / 8000, 2.0) * 100)) into v
--   from unnest(array[null,null,null,null,8000,8000,8000]::int[]) x;
--   if v <> 300 then raise exception 'late joiner: %', v; end if;
--   -- ties [300, 300, 200] → places [1, 1, 3]
--   if (select string_agg(p::text, ',' order by s desc, p) from (
--         select s, rank() over (order by s desc) as p from unnest(array[300,300,200]) s) t) <> '1,1,3' then
--     raise exception 'ties';
--   end if;
--   -- freeze for end 2026-10-12 = 2026-10-15 12:00 UTC
--   if ((date '2026-10-12' + 3)::timestamp + interval '12 hours') at time zone 'UTC' <> timestamptz '2026-10-15 12:00:00+00' then
--     raise exception 'freeze_at';
--   end if;
--   raise notice 'SELFTEST passed';
-- end $$;
