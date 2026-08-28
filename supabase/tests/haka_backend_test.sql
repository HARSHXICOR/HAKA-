begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(18);

insert into auth.users(id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values
  ('00000000-0000-4000-8000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@example.test', 'test', clock_timestamp(), clock_timestamp(), clock_timestamp()),
  ('00000000-0000-4000-8000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@example.test', 'test', clock_timestamp(), clock_timestamp(), clock_timestamp()),
  ('00000000-0000-4000-8000-00000000000c', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c@example.test', 'test', clock_timestamp(), clock_timestamp(), clock_timestamp());

create temporary table haka_test_context as
select public.backend_create_couple(
  '00000000-0000-4000-8000-00000000000a', 'UTC', 'A'
) as created;

select ok((created ->> 'coupleId') is not null, 'createCouple returns a couple ID') from haka_test_context;
select matches(created ->> 'inviteCode', '^[A-Z0-9]{4}-[A-Z0-9]{4}$', 'createCouple returns a valid invite') from haka_test_context;
select is((select count(*)::integer from public.couple_members), 1, 'owner membership is created');
select is((select score from public.heart_state), 10000, 'heart starts at 100 percent');

create temporary table haka_join_result as
select public.backend_redeem_invite(
  '00000000-0000-4000-8000-00000000000b',
  (select created ->> 'inviteCode' from haka_test_context)
) as joined;

select is(
  (select joined ->> 'coupleId' from haka_join_result),
  (select created ->> 'coupleId' from haka_test_context),
  'redeemInvite joins the same couple'
);
select is((select count(*)::integer from public.couple_members), 2, 'couple has exactly two members');

create temporary table haka_tap_one as
select public.backend_tap_heart(
  '00000000-0000-4000-8000-00000000000a',
  (select (created ->> 'coupleId')::uuid from haka_test_context),
  '10000000-0000-4000-8000-000000000001'
) as envelope;

select is((select (envelope -> 'result' ->> 'duplicate')::boolean from haka_tap_one), false, 'first tap is accepted once');
select is((select (envelope -> 'result' ->> 'totalTaps')::bigint from haka_tap_one), 1::bigint, 'first tap increments total');

create temporary table haka_tap_duplicate as
select public.backend_tap_heart(
  '00000000-0000-4000-8000-00000000000a',
  (select (created ->> 'coupleId')::uuid from haka_test_context),
  '10000000-0000-4000-8000-000000000001'
) as envelope;

select is((select (envelope -> 'result' ->> 'duplicate')::boolean from haka_tap_duplicate), true, 'duplicate tap is reported');
select is((select total_taps from public.heart_state), 1::bigint, 'duplicate tap does not increment total');

update public.heart_state set score = 8000, last_updated_at = clock_timestamp() - interval '1 hour';
create temporary table haka_partner_tap as
select public.backend_tap_heart(
  '00000000-0000-4000-8000-00000000000b',
  (select (created ->> 'coupleId')::uuid from haka_test_context),
  '10000000-0000-4000-8000-000000000002'
) as envelope;

select is((select (envelope -> 'result' ->> 'score')::integer from haka_partner_tap), 7025, 'one hour decay and tap produce 7025');
select is((select (envelope -> 'result' -> 'today' ->> 'completed')::boolean from haka_partner_tap), true, 'both partners tapping completes the day');
select is((select current_count from public.streaks), 1, 'completion starts streak at one');
select is((select longest_count from public.streaks), 1, 'completion updates longest streak');

select throws_ok(
  format(
    'select public.backend_tap_heart(%L::uuid, %L::uuid, %L::uuid)',
    '00000000-0000-4000-8000-00000000000c',
    (select created ->> 'coupleId' from haka_test_context),
    '10000000-0000-4000-8000-000000000003'
  ),
  'P0001',
  'HAKA_PERMISSION_DENIED',
  'outsider tap is denied'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000000a', true);
select is((select count(*)::integer from public.heart_state), 1, 'member can read own heart through RLS');
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000000c', true);
select is((select count(*)::integer from public.heart_state), 0, 'outsider cannot read heart through RLS');
select throws_ok(
  'update public.heart_state set score = 1',
  '42501',
  null,
  'authenticated clients cannot mutate authoritative heart state'
);

reset role;
select * from finish();
rollback;
