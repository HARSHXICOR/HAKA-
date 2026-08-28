create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text check (display_name is null or char_length(display_name) between 1 and 40),
  created_at timestamptz not null default clock_timestamp()
);

create table public.couples (
  id uuid primary key default gen_random_uuid(),
  timezone text not null,
  status text not null default 'active' check (status in ('active', 'closed')),
  created_at timestamptz not null default clock_timestamp()
);

create table public.couple_members (
  couple_id uuid not null references public.couples(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'partner')),
  joined_at timestamptz not null default clock_timestamp(),
  primary key (couple_id, user_id),
  unique (user_id)
);

create unique index couple_one_owner on public.couple_members(couple_id) where role = 'owner';
create unique index couple_one_partner on public.couple_members(couple_id) where role = 'partner';

create table public.invites (
  code text primary key check (code ~ '^[A-Z0-9]{4}-[A-Z0-9]{4}$'),
  couple_id uuid not null references public.couples(id) on delete cascade,
  creator_uid uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending', 'redeemed', 'expired')),
  redeemed_by uuid references auth.users(id) on delete set null,
  redeemed_at timestamptz,
  created_at timestamptz not null default clock_timestamp()
);

create index invites_expiry_idx on public.invites(expires_at);

create table public.heart_state (
  couple_id uuid primary key references public.couples(id) on delete cascade,
  score integer not null default 10000 check (score between 0 and 10000),
  max_score integer not null default 10000 check (max_score = 10000),
  total_taps bigint not null default 0 check (total_taps >= 0),
  last_updated_at timestamptz not null default clock_timestamp(),
  last_tap_at timestamptz
);

create table public.daily_stats (
  couple_id uuid not null references public.couples(id) on delete cascade,
  day date not null,
  taps_by_user jsonb not null default '{}'::jsonb,
  total_taps integer not null default 0 check (total_taps >= 0),
  completed boolean not null default false,
  completed_at timestamptz,
  primary key (couple_id, day)
);

create table public.streaks (
  couple_id uuid primary key references public.couples(id) on delete cascade,
  current_count integer not null default 0 check (current_count >= 0),
  longest_count integer not null default 0 check (longest_count >= 0),
  last_completed_date date
);

create table public.devices (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null check (char_length(device_id) between 1 and 128),
  fcm_token text not null check (char_length(fcm_token) between 1 and 4096),
  notifications_enabled boolean not null default true,
  updated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, device_id)
);

create table private.processed_taps (
  couple_id uuid not null references public.couples(id) on delete cascade,
  tap_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  accepted_at timestamptz not null,
  expires_at timestamptz not null,
  response jsonb not null,
  primary key (couple_id, tap_id)
);

create index processed_taps_rate_idx on private.processed_taps(couple_id, accepted_at);
create index processed_taps_user_rate_idx on private.processed_taps(couple_id, user_id, accepted_at);
create index processed_taps_expiry_idx on private.processed_taps(expires_at);

create table private.notification_state (
  couple_id uuid not null references public.couples(id) on delete cascade,
  recipient_uid uuid not null references auth.users(id) on delete cascade,
  last_partner_tap_at timestamptz not null,
  primary key (couple_id, recipient_uid)
);

create or replace function private.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  insert into public.profiles(id, display_name, created_at)
  values (new.id, nullif(left(coalesce(new.raw_user_meta_data ->> 'display_name', ''), 40), ''), clock_timestamp())
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.create_profile_for_new_user();

create or replace function private.is_couple_member(p_couple_id uuid, p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select exists (
    select 1 from public.couple_members
    where couple_id = p_couple_id and user_id = p_uid
  );
$$;

create or replace function private.can_view_profile(p_viewer uuid, p_profile uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select p_viewer = p_profile or exists (
    select 1
    from public.couple_members mine
    join public.couple_members theirs on theirs.couple_id = mine.couple_id
    where mine.user_id = p_viewer and theirs.user_id = p_profile
  );
$$;

grant execute on function private.is_couple_member(uuid, uuid) to authenticated;
grant execute on function private.can_view_profile(uuid, uuid) to authenticated;

create or replace function private.cleanup_expired(p_now timestamptz)
returns void
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
begin
  update public.invites
  set status = 'expired'
  where status = 'pending' and expires_at <= p_now;

  delete from public.invites
  where status <> 'pending' and expires_at + interval '7 days' <= p_now;

  delete from private.processed_taps where expires_at <= p_now;
end;
$$;

create or replace function private.roll_to_day(p_couple_id uuid, p_day date, p_now timestamptz)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_last date;
begin
  select last_completed_date into v_last
  from public.streaks where couple_id = p_couple_id for update;

  if v_last is null or v_last < p_day - 1 then
    update public.streaks set current_count = 0 where couple_id = p_couple_id;
  end if;

  insert into public.daily_stats(couple_id, day)
  values (p_couple_id, p_day)
  on conflict (couple_id, day) do nothing;
end;
$$;

create or replace function private.public_state(p_couple_id uuid, p_uid uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
  v_heart public.heart_state%rowtype;
  v_daily public.daily_stats%rowtype;
  v_streak public.streaks%rowtype;
  v_partner_taps integer := 0;
  v_my_taps integer := 0;
begin
  select * into v_heart from public.heart_state where couple_id = p_couple_id;
  select * into v_daily from public.daily_stats
    where couple_id = p_couple_id order by day desc limit 1;
  select * into v_streak from public.streaks where couple_id = p_couple_id;

  v_my_taps := coalesce((v_daily.taps_by_user ->> p_uid::text)::integer, 0);
  select coalesce(sum(coalesce((v_daily.taps_by_user ->> cm.user_id::text)::integer, 0)), 0)::integer
  into v_partner_taps
  from public.couple_members cm
  where cm.couple_id = p_couple_id and cm.user_id <> p_uid;

  return jsonb_build_object(
    'heart', jsonb_build_object(
      'score', v_heart.score,
      'maxScore', v_heart.max_score,
      'totalTaps', v_heart.total_taps,
      'lastUpdatedAt', extract(epoch from v_heart.last_updated_at)::bigint,
      'lastTapAt', case when v_heart.last_tap_at is null then null else extract(epoch from v_heart.last_tap_at)::bigint end
    ),
    'today', jsonb_build_object(
      'date', v_daily.day::text,
      'tapsByUser', v_daily.taps_by_user,
      'myTaps', v_my_taps,
      'partnerTaps', v_partner_taps,
      'totalTaps', v_daily.total_taps,
      'completed', v_daily.completed,
      'completedAt', case when v_daily.completed_at is null then null else extract(epoch from v_daily.completed_at)::bigint end
    ),
    'streak', jsonb_build_object(
      'current', v_streak.current_count,
      'longest', v_streak.longest_count,
      'lastCompletedDate', v_streak.last_completed_date
    )
  );
end;
$$;

create or replace function public.backend_create_couple(
  p_uid uuid,
  p_timezone text,
  p_display_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions, pg_catalog
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_couple_id uuid;
  v_code text;
  v_day date;
begin
  if p_uid is null then raise exception 'HAKA_UNAUTHENTICATED'; end if;
  if p_timezone is null or char_length(p_timezone) > 64 or not exists (
    select 1 from pg_catalog.pg_timezone_names where name = p_timezone
  ) then raise exception 'HAKA_INVALID_TIMEZONE'; end if;
  if p_display_name is not null and char_length(p_display_name) not between 1 and 40 then
    raise exception 'HAKA_INVALID_DISPLAY_NAME';
  end if;

  perform private.cleanup_expired(v_now);
  insert into public.profiles(id, display_name) values (p_uid, p_display_name)
    on conflict (id) do update set display_name = coalesce(excluded.display_name, public.profiles.display_name);
  perform 1 from public.profiles where id = p_uid for update;
  if exists (select 1 from public.couple_members where user_id = p_uid) then
    raise exception 'HAKA_ALREADY_PAIRED';
  end if;

  insert into public.couples(timezone) values (p_timezone) returning id into v_couple_id;
  insert into public.couple_members(couple_id, user_id, role) values (v_couple_id, p_uid, 'owner');
  insert into public.heart_state(couple_id, last_updated_at) values (v_couple_id, v_now);
  insert into public.streaks(couple_id) values (v_couple_id);
  v_day := (v_now at time zone p_timezone)::date;
  insert into public.daily_stats(couple_id, day) values (v_couple_id, v_day);

  loop
    v_code := upper(substr(encode(extensions.gen_random_bytes(4), 'hex'), 1, 4) || '-' || substr(encode(extensions.gen_random_bytes(4), 'hex'), 1, 4));
    begin
      insert into public.invites(code, couple_id, creator_uid, expires_at)
      values (v_code, v_couple_id, p_uid, v_now + interval '15 minutes');
      exit;
    exception when unique_violation then null;
    end;
  end loop;

  return jsonb_build_object(
    'coupleId', v_couple_id,
    'inviteCode', v_code,
    'expiresAt', extract(epoch from v_now + interval '15 minutes')::bigint
  );
end;
$$;

create or replace function public.backend_redeem_invite(p_uid uuid, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_invite public.invites%rowtype;
  v_member_count integer;
begin
  if p_uid is null then raise exception 'HAKA_UNAUTHENTICATED'; end if;
  p_code := upper(coalesce(p_code, ''));
  if p_code !~ '^[A-Z0-9]{4}-[A-Z0-9]{4}$' then raise exception 'HAKA_INVALID_INVITE'; end if;
  perform private.cleanup_expired(v_now);
  insert into public.profiles(id) values (p_uid) on conflict (id) do nothing;
  perform 1 from public.profiles where id = p_uid for update;
  if exists (select 1 from public.couple_members where user_id = p_uid) then raise exception 'HAKA_ALREADY_PAIRED'; end if;

  select * into v_invite from public.invites where code = p_code for update;
  if not found or v_invite.status <> 'pending' or v_invite.expires_at <= v_now then raise exception 'HAKA_INVITE_UNAVAILABLE'; end if;
  if v_invite.creator_uid = p_uid then raise exception 'HAKA_SELF_PAIR'; end if;
  perform 1 from public.couples where id = v_invite.couple_id for update;
  select count(*) into v_member_count from public.couple_members where couple_id = v_invite.couple_id;
  if v_member_count <> 1 then raise exception 'HAKA_COUPLE_FULL'; end if;

  insert into public.couple_members(couple_id, user_id, role) values (v_invite.couple_id, p_uid, 'partner');
  update public.invites set status = 'redeemed', redeemed_by = p_uid, redeemed_at = v_now where code = p_code;
  return jsonb_build_object('coupleId', v_invite.couple_id);
end;
$$;

create or replace function public.backend_get_bootstrap(p_uid uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_profile public.profiles%rowtype;
  v_couple public.couples%rowtype;
  v_heart public.heart_state%rowtype;
  v_day date;
  v_intervals bigint;
  v_members jsonb;
begin
  if p_uid is null then raise exception 'HAKA_UNAUTHENTICATED'; end if;
  perform private.cleanup_expired(v_now);
  insert into public.profiles(id) values (p_uid) on conflict (id) do nothing;
  select * into v_profile from public.profiles where id = p_uid;
  select c.* into v_couple from public.couples c join public.couple_members cm on cm.couple_id = c.id where cm.user_id = p_uid;
  if not found then
    return jsonb_build_object('uid', p_uid, 'user', jsonb_build_object(
      'displayName', v_profile.display_name,
      'coupleId', null,
      'createdAt', extract(epoch from v_profile.created_at)::bigint
    ), 'couple', null);
  end if;

  select * into v_heart from public.heart_state where couple_id = v_couple.id for update;
  v_intervals := floor(greatest(0, extract(epoch from (v_now - v_heart.last_updated_at))) / 30)::bigint;
  if v_intervals > 0 then
    update public.heart_state set
      score = greatest(0, score - (v_intervals * 100)::integer),
      last_updated_at = last_updated_at + (v_intervals * interval '30 seconds')
    where couple_id = v_couple.id;
  end if;
  v_day := (v_now at time zone v_couple.timezone)::date;
  perform private.roll_to_day(v_couple.id, v_day, v_now);
  select jsonb_object_agg(user_id::text, role) into v_members from public.couple_members where couple_id = v_couple.id;

  return jsonb_build_object(
    'uid', p_uid,
    'user', jsonb_build_object(
      'displayName', v_profile.display_name,
      'coupleId', v_couple.id,
      'createdAt', extract(epoch from v_profile.created_at)::bigint
    ),
    'couple', jsonb_build_object(
      'coupleId', v_couple.id,
      'members', v_members,
      'timezone', v_couple.timezone,
      'status', v_couple.status,
      'createdAt', extract(epoch from v_couple.created_at)::bigint,
      'state', private.public_state(v_couple.id, p_uid)
    )
  );
end;
$$;

create or replace function public.backend_tap_heart(p_uid uuid, p_couple_id uuid, p_tap_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_couple public.couples%rowtype;
  v_heart public.heart_state%rowtype;
  v_daily public.daily_stats%rowtype;
  v_streak public.streaks%rowtype;
  v_existing jsonb;
  v_day date;
  v_intervals bigint;
  v_members uuid[];
  v_member uuid;
  v_partner uuid;
  v_user_rate integer;
  v_couple_rate integer;
  v_all_tapped boolean;
  v_notify boolean := false;
  v_result jsonb;
  v_my_taps integer;
  v_partner_taps integer;
begin
  if p_uid is null then raise exception 'HAKA_UNAUTHENTICATED'; end if;
  if p_couple_id is null or p_tap_id is null then raise exception 'HAKA_INVALID_ARGUMENT'; end if;
  perform private.cleanup_expired(v_now);
  select * into v_couple from public.couples where id = p_couple_id for update;
  if not found then raise exception 'HAKA_COUPLE_NOT_FOUND'; end if;
  select array_agg(user_id order by joined_at) into v_members from public.couple_members where couple_id = p_couple_id;
  if coalesce(array_length(v_members, 1), 0) <> 2 then raise exception 'HAKA_COUPLE_INCOMPLETE'; end if;
  if not (p_uid = any(v_members)) then raise exception 'HAKA_PERMISSION_DENIED'; end if;

  select * into v_heart from public.heart_state where couple_id = p_couple_id for update;
  select response into v_existing from private.processed_taps where couple_id = p_couple_id and tap_id = p_tap_id;
  if found then return jsonb_build_object('result', v_existing || jsonb_build_object('duplicate', true), 'notifyEligible', false, 'partnerUid', null); end if;

  select count(*) into v_user_rate from private.processed_taps
    where couple_id = p_couple_id and user_id = p_uid and accepted_at >= v_now - interval '1 second';
  select count(*) into v_couple_rate from private.processed_taps
    where couple_id = p_couple_id and accepted_at >= v_now - interval '1 second';
  if v_user_rate >= 20 or v_couple_rate >= 50 then raise exception 'HAKA_RATE_LIMITED'; end if;

  v_day := (v_now at time zone v_couple.timezone)::date;
  perform private.roll_to_day(p_couple_id, v_day, v_now);
  v_intervals := floor(greatest(0, extract(epoch from (v_now - v_heart.last_updated_at))) / 30)::bigint;
  update public.heart_state set
    score = least(max_score, greatest(0, score - (v_intervals * 100)::integer) + 25),
    total_taps = total_taps + 1,
    last_tap_at = v_now,
    last_updated_at = last_updated_at + (v_intervals * interval '30 seconds')
  where couple_id = p_couple_id returning * into v_heart;

  update public.daily_stats set
    taps_by_user = jsonb_set(
      taps_by_user,
      array[p_uid::text],
      to_jsonb(coalesce((taps_by_user ->> p_uid::text)::integer, 0) + 1),
      true
    ),
    total_taps = total_taps + 1
  where couple_id = p_couple_id and day = v_day returning * into v_daily;

  v_all_tapped := true;
  foreach v_member in array v_members loop
    if coalesce((v_daily.taps_by_user ->> v_member::text)::integer, 0) = 0 then v_all_tapped := false; end if;
    if v_member <> p_uid then v_partner := v_member; end if;
  end loop;

  if v_all_tapped and not v_daily.completed then
    update public.daily_stats set completed = true, completed_at = v_now
      where couple_id = p_couple_id and day = v_day returning * into v_daily;
    update public.streaks set
      current_count = case when last_completed_date = v_day - 1 then current_count + 1 else 1 end,
      longest_count = greatest(longest_count, case when last_completed_date = v_day - 1 then current_count + 1 else 1 end),
      last_completed_date = v_day
    where couple_id = p_couple_id returning * into v_streak;
  else
    select * into v_streak from public.streaks where couple_id = p_couple_id;
  end if;

  v_my_taps := coalesce((v_daily.taps_by_user ->> p_uid::text)::integer, 0);
  v_partner_taps := coalesce((v_daily.taps_by_user ->> v_partner::text)::integer, 0);
  v_result := jsonb_build_object(
    'accepted', true,
    'duplicate', false,
    'score', v_heart.score,
    'percentage', round(v_heart.score::numeric / 100, 2),
    'totalTaps', v_heart.total_taps,
    'today', jsonb_build_object('myTaps', v_my_taps, 'partnerTaps', v_partner_taps, 'totalTaps', v_daily.total_taps, 'completed', v_daily.completed),
    'streak', jsonb_build_object('current', v_streak.current_count, 'longest', v_streak.longest_count, 'lastCompletedDate', v_streak.last_completed_date)
  );

  insert into private.processed_taps(couple_id, tap_id, user_id, accepted_at, expires_at, response)
  values (p_couple_id, p_tap_id, p_uid, v_now, v_now + interval '7 days', v_result);

  insert into private.notification_state(couple_id, recipient_uid, last_partner_tap_at)
  values (p_couple_id, v_partner, v_now)
  on conflict (couple_id, recipient_uid) do update
    set last_partner_tap_at = excluded.last_partner_tap_at
    where private.notification_state.last_partner_tap_at <= excluded.last_partner_tap_at - interval '5 minutes'
  returning true into v_notify;

  return jsonb_build_object('result', v_result, 'notifyEligible', coalesce(v_notify, false), 'partnerUid', v_partner);
end;
$$;

revoke all on function public.backend_create_couple(uuid, text, text) from public, anon, authenticated;
revoke all on function public.backend_redeem_invite(uuid, text) from public, anon, authenticated;
revoke all on function public.backend_get_bootstrap(uuid) from public, anon, authenticated;
revoke all on function public.backend_tap_heart(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.backend_create_couple(uuid, text, text) to service_role;
grant execute on function public.backend_redeem_invite(uuid, text) to service_role;
grant execute on function public.backend_get_bootstrap(uuid) to service_role;
grant execute on function public.backend_tap_heart(uuid, uuid, uuid) to service_role;

alter table public.profiles enable row level security;
alter table public.couples enable row level security;
alter table public.couple_members enable row level security;
alter table public.invites enable row level security;
alter table public.heart_state enable row level security;
alter table public.daily_stats enable row level security;
alter table public.streaks enable row level security;
alter table public.devices enable row level security;

create policy profiles_select on public.profiles for select to authenticated
using (private.can_view_profile((select auth.uid()), id));
create policy profiles_update_own on public.profiles for update to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);
create policy couples_select_member on public.couples for select to authenticated
using (private.is_couple_member(id, (select auth.uid())));
create policy members_select_member on public.couple_members for select to authenticated
using (private.is_couple_member(couple_id, (select auth.uid())));
create policy heart_select_member on public.heart_state for select to authenticated
using (private.is_couple_member(couple_id, (select auth.uid())));
create policy daily_select_member on public.daily_stats for select to authenticated
using (private.is_couple_member(couple_id, (select auth.uid())));
create policy streak_select_member on public.streaks for select to authenticated
using (private.is_couple_member(couple_id, (select auth.uid())));
create policy devices_select_own on public.devices for select to authenticated
using ((select auth.uid()) = user_id);
create policy devices_insert_own on public.devices for insert to authenticated
with check ((select auth.uid()) = user_id);
create policy devices_update_own on public.devices for update to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy devices_delete_own on public.devices for delete to authenticated
using ((select auth.uid()) = user_id);

grant select on public.profiles, public.couples, public.couple_members, public.heart_state, public.daily_stats, public.streaks to authenticated;
grant select, insert, update, delete on public.devices to authenticated;
revoke all on public.invites from anon, authenticated;

do $$
begin
  alter publication supabase_realtime add table public.heart_state;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.daily_stats;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.streaks;
exception when duplicate_object then null;
end $$;

alter table public.heart_state replica identity full;
alter table public.daily_stats replica identity full;
alter table public.streaks replica identity full;
