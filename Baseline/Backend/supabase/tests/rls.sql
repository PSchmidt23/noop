-- pgTAP: who can read what (FRIENDS_SPEC.md §10 "rls.sql"). Users: A (shares), B (A's friend), C (a stranger).
-- Impersonation: `set local role authenticated` plus the JWT claims auth.uid() reads.
begin;
create extension if not exists pgtap with schema extensions;
select plan(23);

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'a@rls.test'),
  ('00000000-0000-4000-8000-00000000000b', 'b@rls.test'),
  ('00000000-0000-4000-8000-00000000000c', 'c@rls.test');
insert into public.profiles (id, display_name, age_confirmed_at) values
  ('00000000-0000-4000-8000-00000000000a', 'Alex',  now()),
  ('00000000-0000-4000-8000-00000000000b', 'Blair', now()),
  ('00000000-0000-4000-8000-00000000000c', 'Casey', now());
-- A shares steps with friends, intensity only in competitions.
insert into public.share_settings (user_id, metric, audience, consent_version) values
  ('00000000-0000-4000-8000-00000000000a', 'steps', 'friends', 1),
  ('00000000-0000-4000-8000-00000000000a', 'intensity', 'competitions', 1),
  ('00000000-0000-4000-8000-00000000000b', 'intensity', 'friends', 1);
insert into public.daily_values (user_id, day, metric, value, source) values
  ('00000000-0000-4000-8000-00000000000a', current_date, 'steps', 9000, 'strap');
insert into public.daily_values (user_id, day, metric, value) values
  ('00000000-0000-4000-8000-00000000000a', current_date, 'intensity', 42),
  ('00000000-0000-4000-8000-00000000000b', current_date, 'intensity', 30);
-- A pending request from B to A: not yet friends.
insert into public.friendships (user_a, user_b, requested_by, status) values
  ('00000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000b',
   '00000000-0000-4000-8000-00000000000b', 'pending');
-- A competition A and B are both in (intensity, total, this week).
insert into public.competitions (id, created_by, metric, mode, start_day, end_day, freeze_at) values
  ('00000000-0000-4000-8000-0000000c0001', '00000000-0000-4000-8000-00000000000b', 'intensity', 'total',
   current_date, current_date + 6, now() + interval '9 days');
insert into public.competition_members (competition_id, user_id, state, locked_goal) values
  ('00000000-0000-4000-8000-0000000c0001', '00000000-0000-4000-8000-00000000000a', 'joined', 150),
  ('00000000-0000-4000-8000-0000000c0001', '00000000-0000-4000-8000-00000000000b', 'joined', 150);

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000b","role":"authenticated"}';

select is((select count(*)::int from public.daily_values where user_id = '00000000-0000-4000-8000-00000000000a'), 0,
          'B sees none of A''s rows while the request is pending');

reset role;
update public.friendships set status = 'accepted', accepted_at = now();
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000b","role":"authenticated"}';

select is((select count(*)::int from public.daily_values where user_id = '00000000-0000-4000-8000-00000000000a'
           and metric = 'steps'), 1, 'after accept, B sees A''s Friends-level steps');
select is((select count(*)::int from public.daily_values where user_id = '00000000-0000-4000-8000-00000000000a'
           and metric = 'intensity'), 0, 'B never sees A''s competitions-only intensity rows');
select ok((public.competition_standings('00000000-0000-4000-8000-0000000c0001') -> 'rows') @>
          '[{"user_id":"00000000-0000-4000-8000-00000000000a","score":42}]'::jsonb,
          'but A''s competitions-only minutes are scored in the shared competition');
select ok(not ((public.competition_standings('00000000-0000-4000-8000-0000000c0001') -> 'my_days')::text like '%42%'),
          'my_days holds only the caller''s own days');
select throws_ok($$ select last_seen_at from public.profiles $$, '42501', null,
                 'B cannot read profiles.last_seen_at');
select throws_ok($$ select updated_at from public.daily_values $$, '42501', null,
                 'B cannot read daily_values.updated_at');

-- Hide: A hides from B.
reset role;
insert into public.friend_hides (owner, viewer) values
  ('00000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-00000000000b');
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000b","role":"authenticated"}';
select is((select count(*)::int from public.daily_values where user_id = '00000000-0000-4000-8000-00000000000a'), 0,
          'a hide cuts visibility');
select is((select count(*)::int from public.friend_hides), 0, 'B cannot see that A hid from them');

-- Block: B blocks A (after the hide is lifted). Both stay members of the competition (B created it, so block_user
-- removes nobody), and the competition has final results.
reset role;
delete from public.friend_hides;
insert into public.blocks (blocker, blocked) values
  ('00000000-0000-4000-8000-00000000000b', '00000000-0000-4000-8000-00000000000a');
insert into public.competition_results (competition_id, user_id, score, place, days_counted, capped_days) values
  ('00000000-0000-4000-8000-0000000c0001', '00000000-0000-4000-8000-00000000000a', 42, 1, 1, 0),
  ('00000000-0000-4000-8000-0000000c0001', '00000000-0000-4000-8000-00000000000b', 30, 2, 1, 0);
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000b","role":"authenticated"}';
select is((select count(*)::int from public.daily_values where user_id = '00000000-0000-4000-8000-00000000000a'), 0,
          'a block cuts visibility');
select is((select count(*)::int from public.competition_results where user_id = '00000000-0000-4000-8000-00000000000a'), 0,
          'a block hides the other person''s competition result, read straight from the table');
select is((select count(*)::int from public.competition_results where user_id = '00000000-0000-4000-8000-00000000000b'), 1,
          'but never your own');
select is((select count(*)::int from public.competition_members where user_id = '00000000-0000-4000-8000-00000000000a'), 0,
          'and their membership row');
reset role;
delete from public.blocks;
delete from public.competition_results;

-- The policy helpers live in private, which the API does not expose: a blocked person cannot ask is_blocked_between.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000b","role":"authenticated"}';
select throws_ok($$ select public.is_blocked_between('00000000-0000-4000-8000-00000000000a') $$, '42883', null,
                 'the policy helpers are not RPCs');
reset role;

-- Stranger C sees nothing, not even A's profile.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000c","role":"authenticated"}';
select is((select count(*)::int from public.daily_values where user_id <> '00000000-0000-4000-8000-00000000000c'), 0,
          'a stranger sees no daily rows');
select is((select count(*)::int from public.profiles where id <> '00000000-0000-4000-8000-00000000000c'), 0,
          'a stranger sees no profiles');

-- Invited is not joined: C, invited to A and B's competition, gets the roster but no scores (A shares intensity only
-- in competitions, and C shares nothing back).
reset role;
insert into public.competition_members (competition_id, user_id, state) values
  ('00000000-0000-4000-8000-0000000c0001', '00000000-0000-4000-8000-00000000000c', 'invited');
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000c","role":"authenticated"}';
select is(public.competition_standings('00000000-0000-4000-8000-0000000c0001') -> 'rows', '[]'::jsonb,
          'an invited member sees no scores until they join');
select is(jsonb_array_length(public.competition_standings('00000000-0000-4000-8000-0000000c0001') -> 'competition' -> 'members'), 3,
          'only the roster');
-- Nor straight from the table once it is final: results go to people who took part, not to someone still invited.
reset role;
insert into public.competition_results (competition_id, user_id, score, place, days_counted, capped_days) values
  ('00000000-0000-4000-8000-0000000c0001', '00000000-0000-4000-8000-00000000000a', 42, 1, 1, 0);
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000c","role":"authenticated"}';
select is((select count(*)::int from public.competition_results), 0,
          'an invited member cannot read final results from the table');
reset role;
delete from public.competition_results;
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000c","role":"authenticated"}';

-- Every direct write from authenticated is denied.
select throws_ok($$ insert into public.daily_values (user_id, day, metric, value)
                    values ('00000000-0000-4000-8000-00000000000c', current_date, 'intensity', 5) $$,
                 '42501', null, 'insert denied');
select throws_ok($$ update public.profiles set display_name = 'Hacker' $$, '42501', null, 'update denied');
select throws_ok($$ delete from public.friendships $$, '42501', null, 'delete denied');

-- anon can execute nothing.
reset role;
set local role anon;
select throws_ok($$ select public.friends_overview(current_date - 1, current_date) $$, '42501', null,
                 'anon cannot call an RPC');

select * from finish();
rollback;
