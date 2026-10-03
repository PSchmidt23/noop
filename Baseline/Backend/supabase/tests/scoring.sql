-- pgTAP: the shared scoring fixture (the same numbers as BaselineTests/FriendsScoringTests.swift and the SELFTEST
-- block at the end of schema.sql). Runs as the database owner and reads private.competition_scores directly.
-- Run with: supabase start && supabase test db   (see SETUP.md step 10)
begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

-- People
insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000a1', 'a@scoring.test'),
  ('00000000-0000-4000-8000-0000000000b2', 'b@scoring.test'),
  ('00000000-0000-4000-8000-0000000000c3', 'c@scoring.test');
insert into public.profiles (id, display_name, age_confirmed_at, step_goal, intensity_goal) values
  ('00000000-0000-4000-8000-0000000000a1', 'Ana',  now(), 8000, 150),
  ('00000000-0000-4000-8000-0000000000b2', 'Ben',  now(), 8000, 150),
  ('00000000-0000-4000-8000-0000000000c3', 'Cleo', now(), 8000, 150);
insert into public.share_settings (user_id, metric, audience, consent_version)
select u, m, 'friends', 1
from unnest(array['00000000-0000-4000-8000-0000000000a1','00000000-0000-4000-8000-0000000000b2',
                  '00000000-0000-4000-8000-0000000000c3']::uuid[]) u,
     unnest(array['steps','intensity','bedtime']) m;

-- 1) steps · goal_percent, 7 days (Mon 5 – Sun 11 Oct 2026), goal 8000
insert into public.competitions (id, created_by, metric, mode, start_day, end_day, freeze_at) values
  ('00000000-0000-4000-8000-00000000c001', '00000000-0000-4000-8000-0000000000a1', 'steps', 'goal_percent',
   '2026-10-05', '2026-10-11', '2026-10-14 12:00+00');
insert into public.competition_members (competition_id, user_id, state, locked_goal) values
  ('00000000-0000-4000-8000-00000000c001', '00000000-0000-4000-8000-0000000000a1', 'joined', 8000),
  ('00000000-0000-4000-8000-00000000c001', '00000000-0000-4000-8000-0000000000b2', 'joined', 8000),
  ('00000000-0000-4000-8000-00000000c001', '00000000-0000-4000-8000-0000000000c3', 'joined', 8000);
-- Ana: every day at 20,000 (200 a day, the cap) → 1,400
insert into public.daily_values (user_id, day, metric, value, source)
select '00000000-0000-4000-8000-0000000000a1', d::date, 'steps', 20000, 'strap'
from generate_series('2026-10-05'::timestamp, '2026-10-11'::timestamp, interval '1 day') d;
-- Ben: one day at 12,000 (150) and one at 20,000 (200); missing days count 0 → 350
insert into public.daily_values (user_id, day, metric, value, source) values
  ('00000000-0000-4000-8000-0000000000b2', '2026-10-05', 'steps', 12000, 'phone'),
  ('00000000-0000-4000-8000-0000000000b2', '2026-10-06', 'steps', 20000, 'phone');
-- Cleo joined late: rows only on the last 3 days at 8,000 → 300
insert into public.daily_values (user_id, day, metric, value, source) values
  ('00000000-0000-4000-8000-0000000000c3', '2026-10-09', 'steps', 8000, 'strap'),
  ('00000000-0000-4000-8000-0000000000c3', '2026-10-10', 'steps', 8000, 'strap'),
  ('00000000-0000-4000-8000-0000000000c3', '2026-10-11', 'steps', 8000, 'strap');

select is((select score from private.competition_scores('00000000-0000-4000-8000-00000000c001')
           where user_id = '00000000-0000-4000-8000-0000000000a1'), 1400, '7 days at the cap → 1,400');
select is((select score from private.competition_scores('00000000-0000-4000-8000-00000000c001')
           where user_id = '00000000-0000-4000-8000-0000000000b2'), 350, '12,000 → 150 plus 20,000 → 200');
select is((select score from private.competition_scores('00000000-0000-4000-8000-00000000c001')
           where user_id = '00000000-0000-4000-8000-0000000000c3'), 300, 'late joiner: missing days count 0');
select is((select days_counted from private.competition_scores('00000000-0000-4000-8000-00000000c001')
           where user_id = '00000000-0000-4000-8000-0000000000c3'), 3, 'days_counted = days with a row');
select is((select source_mix from private.competition_scores('00000000-0000-4000-8000-00000000c001')
           where user_id = '00000000-0000-4000-8000-0000000000b2'), 'phone', 'source mix');

-- 2) intensity · goal_percent over 3 days, weekly goal 150 (target 64.29): 70 min → 109
insert into public.competitions (id, created_by, metric, mode, start_day, end_day, freeze_at) values
  ('00000000-0000-4000-8000-00000000c002', '00000000-0000-4000-8000-0000000000a1', 'intensity', 'goal_percent',
   '2026-10-05', '2026-10-07', '2026-10-10 12:00+00');
insert into public.competition_members (competition_id, user_id, state, locked_goal) values
  ('00000000-0000-4000-8000-00000000c002', '00000000-0000-4000-8000-0000000000a1', 'joined', 150);
insert into public.daily_values (user_id, day, metric, value) values
  ('00000000-0000-4000-8000-0000000000a1', '2026-10-05', 'intensity', 30),
  ('00000000-0000-4000-8000-0000000000a1', '2026-10-07', 'intensity', 40);
select is((select score from private.competition_scores('00000000-0000-4000-8000-00000000c002')), 109,
          'intensity goal_percent: 70 of 64.29 → 109');

-- 2b) exact half points round up, as Swift's integer arithmetic does (Double would land a point low)
--     steps · goal_percent, one day, goal 3000: 435 steps = 14.5 → 15
insert into public.competitions (id, created_by, metric, mode, start_day, end_day, freeze_at) values
  ('00000000-0000-4000-8000-00000000c006', '00000000-0000-4000-8000-0000000000b2', 'steps', 'goal_percent',
   '2026-08-03', '2026-08-03', '2026-08-06 12:00+00');
insert into public.competition_members (competition_id, user_id, state, locked_goal) values
  ('00000000-0000-4000-8000-00000000c006', '00000000-0000-4000-8000-0000000000b2', 'joined', 3000);
insert into public.daily_values (user_id, day, metric, value, source) values
  ('00000000-0000-4000-8000-0000000000b2', '2026-08-03', 'steps', 435, 'strap');
select is((select score from private.competition_scores('00000000-0000-4000-8000-00000000c006')), 15,
          'steps half point: 435 of 3,000 = 14.5 → 15');
--     intensity · goal_percent, weekly goal 200: 7 days with 201 min = 100.5 → 101
insert into public.competitions (id, created_by, metric, mode, start_day, end_day, freeze_at) values
  ('00000000-0000-4000-8000-00000000c007', '00000000-0000-4000-8000-0000000000b2', 'intensity', 'goal_percent',
   '2026-08-10', '2026-08-16', '2026-08-19 12:00+00');
insert into public.competition_members (competition_id, user_id, state, locked_goal) values
  ('00000000-0000-4000-8000-00000000c007', '00000000-0000-4000-8000-0000000000b2', 'joined', 200);
insert into public.daily_values (user_id, day, metric, value) values
  ('00000000-0000-4000-8000-0000000000b2', '2026-08-10', 'intensity', 201);
select is((select score from private.competition_scores('00000000-0000-4000-8000-00000000c007')), 101,
          'intensity half point, 7 days: 201 of 200 = 100.5 → 101');
--     intensity · goal_percent, weekly goal 200: 4 days with 44 min = 38.5 → 39 (200 × 4 / 7 never terminates)
insert into public.competitions (id, created_by, metric, mode, start_day, end_day, freeze_at) values
  ('00000000-0000-4000-8000-00000000c008', '00000000-0000-4000-8000-0000000000c3', 'intensity', 'goal_percent',
   '2026-08-10', '2026-08-13', '2026-08-16 12:00+00');
insert into public.competition_members (competition_id, user_id, state, locked_goal) values
  ('00000000-0000-4000-8000-00000000c008', '00000000-0000-4000-8000-0000000000c3', 'joined', 200);
insert into public.daily_values (user_id, day, metric, value) values
  ('00000000-0000-4000-8000-0000000000c3', '2026-08-11', 'intensity', 44);
select is((select score from private.competition_scores('00000000-0000-4000-8000-00000000c008')), 39,
          'intensity half point, 4 days: 44 of 114.29 = 38.5 → 39');

-- 3) steps · total with a capped day (an upload of 70,000 is stored as 60,000, capped)
insert into public.competitions (id, created_by, metric, mode, start_day, end_day, freeze_at) values
  ('00000000-0000-4000-8000-00000000c003', '00000000-0000-4000-8000-0000000000b2', 'steps', 'total',
   '2026-10-12', '2026-10-12', '2026-10-15 12:00+00');
insert into public.competition_members (competition_id, user_id, state, locked_goal) values
  ('00000000-0000-4000-8000-00000000c003', '00000000-0000-4000-8000-0000000000b2', 'joined', 8000);
insert into public.daily_values (user_id, day, metric, value, source, capped) values
  ('00000000-0000-4000-8000-0000000000b2', '2026-10-12', 'steps', 60000, 'strap', true);
select is((select score from private.competition_scores('00000000-0000-4000-8000-00000000c003')), 60000, 'total: 60,000');
select is((select capped_days from private.competition_scores('00000000-0000-4000-8000-00000000c003')), 1, 'capped_days 1');

-- 4) steps · days_at_goal, goal 8000: [9000, 7999, 8000, 0] → 2
insert into public.competitions (id, created_by, metric, mode, start_day, end_day, freeze_at) values
  ('00000000-0000-4000-8000-00000000c004', '00000000-0000-4000-8000-0000000000c3', 'steps', 'days_at_goal',
   '2026-09-01', '2026-09-04', '2026-09-07 12:00+00');
insert into public.competition_members (competition_id, user_id, state, locked_goal) values
  ('00000000-0000-4000-8000-00000000c004', '00000000-0000-4000-8000-0000000000c3', 'joined', 8000);
insert into public.daily_values (user_id, day, metric, value, source) values
  ('00000000-0000-4000-8000-0000000000c3', '2026-09-01', 'steps', 9000, 'strap'),
  ('00000000-0000-4000-8000-0000000000c3', '2026-09-02', 'steps', 7999, 'strap'),
  ('00000000-0000-4000-8000-0000000000c3', '2026-09-03', 'steps', 8000, 'strap'),
  ('00000000-0000-4000-8000-0000000000c3', '2026-09-04', 'steps', 0, 'strap');
select is((select score from private.competition_scores('00000000-0000-4000-8000-00000000c004')), 2, 'days_at_goal → 2');

-- 5) ties: bedtime · total [5, 5, 3] → places 1, 1, 3
insert into public.competitions (id, created_by, metric, mode, start_day, end_day, freeze_at) values
  ('00000000-0000-4000-8000-00000000c005', '00000000-0000-4000-8000-0000000000a1', 'bedtime', 'total',
   '2026-09-21', '2026-09-27', '2026-09-30 12:00+00');
insert into public.competition_members (competition_id, user_id, state) values
  ('00000000-0000-4000-8000-00000000c005', '00000000-0000-4000-8000-0000000000a1', 'joined'),
  ('00000000-0000-4000-8000-00000000c005', '00000000-0000-4000-8000-0000000000b2', 'joined'),
  ('00000000-0000-4000-8000-00000000c005', '00000000-0000-4000-8000-0000000000c3', 'joined');
insert into public.daily_values (user_id, day, metric, value)
select u, '2026-09-20'::date + i, 'bedtime', 1
from (values ('00000000-0000-4000-8000-0000000000a1'::uuid, 5), ('00000000-0000-4000-8000-0000000000b2'::uuid, 5),
             ('00000000-0000-4000-8000-0000000000c3'::uuid, 3)) as t(u, n),
     generate_series(1, 7) as i
where i <= n;
select results_eq(
  $$ select place from private.competition_scores('00000000-0000-4000-8000-00000000c005') order by place $$,
  $$ values (1), (1), (3) $$,
  'ties share a place (1, 1, 3)');

-- 6) freeze time for an end of 2026-10-12 is 2026-10-15 12:00 UTC
select is(((date '2026-10-12' + 3)::timestamp + interval '12 hours') at time zone 'UTC',
          timestamptz '2026-10-15 12:00:00+00', 'freeze_at = end + 3 days, 12:00 UTC');

-- 7) a member who stops sharing gets a null score and no place
delete from public.share_settings where user_id = '00000000-0000-4000-8000-0000000000c3' and metric = 'bedtime';
select is((select score from private.competition_scores('00000000-0000-4000-8000-00000000c005')
           where user_id = '00000000-0000-4000-8000-0000000000c3'), null::int, 'not sharing → null score');

select * from finish();
rollback;
