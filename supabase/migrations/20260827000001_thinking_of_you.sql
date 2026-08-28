-- Private, idempotent partner nudges. This does not change heart score.
create table if not exists private.thinking_of_you_events (
  couple_id uuid not null references public.couples(id) on delete cascade,
  event_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default clock_timestamp(),
  primary key (couple_id, event_id)
);

create index if not exists thinking_of_you_rate_idx
  on private.thinking_of_you_events(couple_id, user_id, created_at);

create or replace function public.backend_thinking_of_you(p_uid uuid, p_couple_id uuid, p_event_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_members uuid[];
  v_partner uuid;
  v_rate integer;
begin
  if p_uid is null or p_couple_id is null or p_event_id is null then raise exception 'HAKA_INVALID_ARGUMENT'; end if;
  perform 1 from public.couples where id = p_couple_id for update;
  if not found then raise exception 'HAKA_COUPLE_NOT_FOUND'; end if;
  select array_agg(user_id order by joined_at) into v_members
    from public.couple_members where couple_id = p_couple_id;
  if coalesce(array_length(v_members, 1), 0) <> 2 then raise exception 'HAKA_COUPLE_INCOMPLETE'; end if;
  if not (p_uid = any(v_members)) then raise exception 'HAKA_PERMISSION_DENIED'; end if;
  if exists (select 1 from private.thinking_of_you_events where couple_id = p_couple_id and event_id = p_event_id) then
    return jsonb_build_object('accepted', false, 'duplicate', true, 'eventId', p_event_id);
  end if;
  select count(*) into v_rate from private.thinking_of_you_events
   where couple_id = p_couple_id and user_id = p_uid and created_at >= v_now - interval '1 minute';
  if v_rate >= 6 then raise exception 'HAKA_THINKING_RATE_LIMITED'; end if;
  foreach v_partner in array v_members loop
    if v_partner <> p_uid then exit; end if;
  end loop;
  insert into private.thinking_of_you_events(couple_id, event_id, user_id, created_at)
    values (p_couple_id, p_event_id, p_uid, v_now);
  return jsonb_build_object('accepted', true, 'duplicate', false, 'eventId', p_event_id, 'partnerUid', v_partner);
end;
$$;

revoke all on function public.backend_thinking_of_you(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.backend_thinking_of_you(uuid, uuid, uuid) to service_role;
