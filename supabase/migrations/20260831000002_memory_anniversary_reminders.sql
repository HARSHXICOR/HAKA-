alter table private.memories add column if not exists last_notified_year integer;

create or replace function public.backend_story_claim_due_dates(p_uid uuid, p_couple_id uuid)
returns jsonb language plpgsql security definer set search_path = public, private, pg_catalog as $$
declare v_timezone text; v_today date; v_partner uuid; v_year integer;
begin
  perform private.require_couple_member(p_uid, p_couple_id);
  select timezone into v_timezone from public.couples where id = p_couple_id;
  v_today := (clock_timestamp() at time zone coalesce(v_timezone, 'UTC'))::date; v_year := extract(year from v_today)::integer;
  select user_id into v_partner from public.couple_members where couple_id=p_couple_id and user_id<>p_uid limit 1;
  if v_partner is null then return '[]'::jsonb; end if;
  return coalesce((with due_dates as (
    update private.relationship_dates set last_notified_year=v_year
    where couple_id=p_couple_id and remind_annually and (last_notified_year is null or last_notified_year <> v_year)
      and extract(month from occurs_on)=extract(month from v_today) and extract(day from occurs_on)=extract(day from v_today)
    returning label
  ), due_memories as (
    update private.memories set last_notified_year=v_year
    where couple_id=p_couple_id and occurred_on is not null and (last_notified_year is null or last_notified_year <> v_year)
      and extract(month from occurred_on)=extract(month from v_today) and extract(day from occurred_on)=extract(day from v_today)
    returning title as label
  ) select jsonb_agg(jsonb_build_object('label',label,'partnerUid',v_partner)) from (select label from due_dates union all select label from due_memories) reminders), '[]'::jsonb);
end; $$;
