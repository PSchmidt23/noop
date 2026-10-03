-- pgTAP: the RPC rules (FRIENDS_SPEC.md §10 "rpc.sql"). Users: A (inviter), B (redeemer), C (third person).
begin;
create extension if not exists pgtap with schema extensions;
select plan(35);

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000aa', 'a@rpc.test'),
  ('00000000-0000-4000-8000-0000000000bb', 'b@rpc.test'),
  ('00000000-0000-4000-8000-0000000000cc', 'c@rpc.test');

set local role authenticated;

-- Profiles through the RPC (16+ required, names validated).
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-0000000000aa","role":"authenticated"}';
select throws_ok($$ select public.complete_profile('Alex', false) $$, 'P0001', 'age_required', '16+ is required');
select throws_ok($$ select public.complete_profile('see www.spam.example', true) $$, 'P0001', 'invalid_name', 'links rejected');
select throws_ok($$ select public.complete_profile('Mr Shit', true) $$, 'P0001', 'invalid_name', 'a short blocked word as a word');
select throws_ok($$ select public.complete_profile('FuckFace', true) $$, 'P0001', 'invalid_name', 'a long one anywhere');
select lives_ok($$ select public.complete_profile('Nazir Hancock', true) $$,
                'real names containing a short blocked word pass (DisplayName.blockedWholeWords)');
select lives_ok($$ select public.complete_profile('Yoshitaka Heilmann', true) $$, 'Yoshitaka, Heilmann');
select lives_ok($$ select public.complete_profile('Isis Pricket', true) $$, 'Isis, Pricket');
select lives_ok($$ select public.complete_profile('  Ana-María  ', true) $$, 'NFKC name, trimmed');
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-0000000000bb","role":"authenticated"}';
select lives_ok($$ select public.complete_profile('Blair', true) $$, 'B profile');
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-0000000000cc","role":"authenticated"}';
select lives_ok($$ select public.complete_profile('Cleo', true) $$, 'C profile');

-- Invites: A creates; B peeks (nothing changes), redeems (pending); reuse and self are refused.
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-0000000000aa","role":"authenticated"}';
create temp table t_code on commit drop as select (public.create_invite() ->> 'code') as code;
select ok((select code from t_code) ~ '^[A-HJ-NP-Z2-9]{8}$', 'server code uses the 32-symbol alphabet');
select is(public.peek_invite((select code from t_code)) ->> 'error', 'invite_self',
          'own code (refusals are returned, not raised, so the rate limit counts them)');

set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-0000000000bb","role":"authenticated"}';
select is(public.peek_invite(lower((select code from t_code))) ->> 'display_name', 'Ana-María', 'peek names the inviter');
select is((select count(*)::int from public.friendships), 0, 'peek changes nothing');
select lives_ok(format('select public.redeem_invite(%L)', (select code from t_code)), 'redeem');
select is((select status from public.friendships), 'pending', 'redeem creates a PENDING request');
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-0000000000cc","role":"authenticated"}';
select is(public.redeem_invite((select code from t_code)) ->> 'error', 'invite_used', 'single use');
select is(public.redeem_invite('ABCD2345') ->> 'error', 'invite_invalid', 'unknown code');
-- Wrong guesses count toward the limit: 30 refused peeks in the hour, then the 31st is rate_limited.
select is((select count(*)::int from generate_series(1, 30) as i
           where public.peek_invite('ZZZZ' || lpad(i::text, 4, '2')) ->> 'error' = 'invite_invalid'), 30,
          '30 wrong codes are each refused');
select throws_ok($$ select public.peek_invite('ZZZZ2345') $$, 'P0001', 'rate_limited',
                 'the 31st peek within an hour is refused, wrong guesses included');

-- The inviter accepts; the requester cannot answer their own request.
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-0000000000bb","role":"authenticated"}';
select throws_ok($$ select public.respond_friend('00000000-0000-4000-8000-0000000000aa', true) $$, 'P0001', 'not_found',
                 'the requester cannot accept');
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-0000000000aa","role":"authenticated"}';
select lives_ok($$ select public.respond_friend('00000000-0000-4000-8000-0000000000bb', true) $$, 'the inviter accepts');

-- Upload: unshared metrics and out-of-window days are dropped; over-cap values are clamped and flagged.
select lives_ok($$ select public.set_share('steps', 'friends', 1) $$, 'share steps');
select is(public.upload(jsonb_build_array(
            jsonb_build_object('day', current_date, 'metric', 'steps', 'value', 70000, 'source', 'strap', 'capped', false),
            jsonb_build_object('day', current_date - 60, 'metric', 'steps', 'value', 5000, 'source', 'strap', 'capped', false),
            jsonb_build_object('day', current_date, 'metric', 'intensity', 'value', 30, 'capped', false)),
          '[]'::jsonb),
          '{"accepted": 1, "dropped": 2}'::jsonb, 'only the shared, in-window row is accepted');
select is((select value from public.daily_values where metric = 'steps' and day = current_date), 60000,
          '70,000 stored as 60,000');
-- A null value retracts the day: the caller's own row is deleted.
select is(public.upload(jsonb_build_array(
            jsonb_build_object('day', current_date, 'metric', 'steps', 'value', null)), '[]'::jsonb),
          '{"accepted": 1, "dropped": 0}'::jsonb, 'a retraction is accepted');
select is((select count(*)::int from public.daily_values where metric = 'steps' and day = current_date), 0,
          'and deletes the row');
select throws_ok($$ select public.set_share('hrv', 'competitions', 1) $$, 'P0001', 'invalid_audience',
                 'physiology is never competitions-only');

-- Withdrawal deletes the rows in the same call.
select lives_ok($$ select public.set_share('steps', null, 1) $$, 'turn steps off');
select is((select count(*)::int from public.daily_values where user_id = '00000000-0000-4000-8000-0000000000aa'), 0,
          'Off deletes the rows');

-- Competitions: metric must be shared; only the creator removes; joining closes the day after the start.
select throws_ok($$ select public.create_competition('steps', 'goal_percent', current_date, current_date + 6,
                                                     array['00000000-0000-4000-8000-0000000000bb']::uuid[]) $$,
                 'P0001', 'metric_not_shared', 'the creator must share the metric');
reset role;
insert into public.competitions (id, created_by, metric, mode, start_day, end_day, freeze_at) values
  ('00000000-0000-4000-8000-00000000cc01', '00000000-0000-4000-8000-0000000000aa', 'steps', 'total',
   current_date - 5, current_date + 1, now() + interval '4 days');
insert into public.competition_members (competition_id, user_id, state) values
  ('00000000-0000-4000-8000-00000000cc01', '00000000-0000-4000-8000-0000000000aa', 'joined'),
  ('00000000-0000-4000-8000-00000000cc01', '00000000-0000-4000-8000-0000000000bb', 'invited');
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-0000000000bb","role":"authenticated"}';
select throws_ok($$ select public.respond_competition('00000000-0000-4000-8000-00000000cc01', true) $$, 'P0001',
                 'joining_closed', 'a late join after start + 1 is refused');
select throws_ok($$ select public.remove_participant('00000000-0000-4000-8000-00000000cc01',
                                                     '00000000-0000-4000-8000-0000000000aa') $$,
                 'P0001', 'not_creator', 'only the creator removes participants');

-- Deleting the account removes every row of that user.
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-0000000000aa","role":"authenticated"}';
select lives_ok($$ select public.delete_account() $$, 'delete the account');
reset role;
select is((select (select count(*) from public.profiles where id = '00000000-0000-4000-8000-0000000000aa')
                + (select count(*) from public.friendships where '00000000-0000-4000-8000-0000000000aa' in (user_a, user_b))
                + (select count(*) from public.consent_log where user_id = '00000000-0000-4000-8000-0000000000aa')
                + (select count(*) from public.competition_members where user_id = '00000000-0000-4000-8000-0000000000aa')
                + (select count(*) from public.invites where created_by = '00000000-0000-4000-8000-0000000000aa'))::int,
          0, 'delete_account leaves zero rows');

select * from finish();
rollback;
