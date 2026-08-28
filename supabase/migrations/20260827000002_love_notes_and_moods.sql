-- V2 private relationship features: Love Notes and Daily Mood.
create table if not exists private.love_notes (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  sender_uid uuid not null references auth.users(id) on delete cascade,
  recipient_uid uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 160),
  created_at timestamptz not null default clock_timestamp(),
  read_at timestamptz
);

create index if not exists love_notes_couple_created_idx
  on private.love_notes(couple_id, created_at desc);

create table if not exists private.daily_moods (
  couple_id uuid not null references public.couples(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  mood text not null check (mood in ('happy', 'loved', 'calm', 'sad', 'missing', 'excited')),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (couple_id, user_id, day)
);

create index if not exists daily_moods_couple_day_idx
  on private.daily_moods(couple_id, day);

create or replace function public.backend_send_love_note(p_uid uuid, p_couple_id uuid, p_body text)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_couple public.couples%rowtype;
  v_partner uuid;
  v_note private.love_notes%rowtype;
  v_rate integer;
begin
  if p_uid is null or p_couple_id is null or char_length(trim(coalesce(p_body, ''))) not between 1 and 160 then
    raise exception 'HAKA_INVALID_ARGUMENT';
  end if;
  select * into v_couple from public.couples where id = p_couple_id for update;
  if not found then raise exception 'HAKA_COUPLE_NOT_FOUND'; end if;
  if not exists (select 1 from public.couple_members where couple_id = p_couple_id and user_id = p_uid) then
    raise exception 'HAKA_PERMISSION_DENIED';
  end if;
  select cm.user_id into v_partner from public.couple_members cm
   where cm.couple_id = p_couple_id and cm.user_id <> p_uid limit 1;
  if v_partner is null then raise exception 'HAKA_COUPLE_INCOMPLETE'; end if;
  select count(*) into v_rate from private.love_notes
   where couple_id = p_couple_id and sender_uid = p_uid and created_at >= clock_timestamp() - interval '1 hour';
  if v_rate >= 20 then raise exception 'HAKA_NOTE_RATE_LIMITED'; end if;
  insert into private.love_notes(couple_id, sender_uid, recipient_uid, body)
    values (p_couple_id, p_uid, v_partner, trim(p_body)) returning * into v_note;
  return jsonb_build_object(
    'id', v_note.id,
    'coupleId', v_note.couple_id,
    'senderUid', v_note.sender_uid,
    'recipientUid', v_note.recipient_uid,
    'body', v_note.body,
    'createdAt', extract(epoch from v_note.created_at)::bigint,
    'readAt', null,
    'partnerUid', v_partner
  );
end;
$$;

create or replace function public.backend_list_love_notes(p_uid uuid, p_couple_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
begin
  if p_uid is null or p_couple_id is null then raise exception 'HAKA_INVALID_ARGUMENT'; end if;
  if not exists (select 1 from public.couple_members where couple_id = p_couple_id and user_id = p_uid) then
    raise exception 'HAKA_PERMISSION_DENIED';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', n.id,
      'coupleId', n.couple_id,
      'senderUid', n.sender_uid,
      'recipientUid', n.recipient_uid,
      'body', n.body,
      'createdAt', extract(epoch from n.created_at)::bigint,
      'readAt', case when n.read_at is null then null else extract(epoch from n.read_at)::bigint end
    ) order by n.created_at desc)
    from (select * from private.love_notes where couple_id = p_couple_id order by created_at desc limit 50) n), '[]'::jsonb);
end;
$$;

create or replace function public.backend_mark_love_note_read(p_uid uuid, p_note_id uuid)
returns void
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
begin
  update private.love_notes n set read_at = coalesce(n.read_at, clock_timestamp())
   where n.id = p_note_id and n.recipient_uid = p_uid;
end;
$$;

create or replace function public.backend_set_daily_mood(p_uid uuid, p_couple_id uuid, p_mood text)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_timezone text;
  v_day date;
  v_now timestamptz := clock_timestamp();
begin
  if p_uid is null or p_couple_id is null or p_mood is null or p_mood not in ('happy', 'loved', 'calm', 'sad', 'missing', 'excited') then
    raise exception 'HAKA_INVALID_ARGUMENT';
  end if;
  select timezone into v_timezone from public.couples where id = p_couple_id;
  if v_timezone is null then raise exception 'HAKA_COUPLE_NOT_FOUND'; end if;
  if not exists (select 1 from public.couple_members where couple_id = p_couple_id and user_id = p_uid) then
    raise exception 'HAKA_PERMISSION_DENIED';
  end if;
  v_day := (v_now at time zone v_timezone)::date;
  insert into private.daily_moods(couple_id, user_id, day, mood, updated_at)
    values (p_couple_id, p_uid, v_day, p_mood, v_now)
  on conflict (couple_id, user_id, day) do update set mood = excluded.mood, updated_at = excluded.updated_at;
  return jsonb_build_object('day', v_day::text, 'mood', p_mood);
end;
$$;

create or replace function public.backend_get_daily_moods(p_uid uuid, p_couple_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_timezone text;
  v_day date;
begin
  if p_uid is null or p_couple_id is null then raise exception 'HAKA_INVALID_ARGUMENT'; end if;
  select timezone into v_timezone from public.couples where id = p_couple_id;
  if v_timezone is null then raise exception 'HAKA_COUPLE_NOT_FOUND'; end if;
  if not exists (select 1 from public.couple_members where couple_id = p_couple_id and user_id = p_uid) then
    raise exception 'HAKA_PERMISSION_DENIED';
  end if;
  v_day := (clock_timestamp() at time zone v_timezone)::date;
  return jsonb_build_object(
    'day', v_day::text,
    'moods', coalesce((select jsonb_object_agg(user_id::text, mood) from private.daily_moods where couple_id = p_couple_id and day = v_day), '{}'::jsonb)
  );
end;
$$;

revoke all on function public.backend_send_love_note(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.backend_list_love_notes(uuid, uuid) from public, anon, authenticated;
revoke all on function public.backend_mark_love_note_read(uuid, uuid) from public, anon, authenticated;
revoke all on function public.backend_set_daily_mood(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.backend_get_daily_moods(uuid, uuid) from public, anon, authenticated;
grant execute on function public.backend_send_love_note(uuid, uuid, text) to service_role;
grant execute on function public.backend_list_love_notes(uuid, uuid) to service_role;
grant execute on function public.backend_mark_love_note_read(uuid, uuid) to service_role;
grant execute on function public.backend_set_daily_mood(uuid, uuid, text) to service_role;
grant execute on function public.backend_get_daily_moods(uuid, uuid) to service_role;
