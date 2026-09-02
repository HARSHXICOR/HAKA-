-- Private image storage is written only by the authenticated Edge Function.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('relationship-media', 'relationship-media', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = false, file_size_limit = 2097152;

create or replace function public.backend_story_claim_due_dates(p_uid uuid, p_couple_id uuid)
returns jsonb language plpgsql security definer set search_path = public, private, pg_catalog as $$
declare v_timezone text; v_today date; v_partner uuid; v_year integer;
begin
  perform private.require_couple_member(p_uid, p_couple_id);
  select timezone into v_timezone from public.couples where id = p_couple_id;
  v_today := (clock_timestamp() at time zone coalesce(v_timezone, 'UTC'))::date; v_year := extract(year from v_today)::integer;
  select user_id into v_partner from public.couple_members where couple_id=p_couple_id and user_id<>p_uid limit 1;
  if v_partner is null then return '[]'::jsonb; end if;
  return coalesce((with due as (
    update private.relationship_dates set last_notified_year=v_year
    where couple_id=p_couple_id and remind_annually and (last_notified_year is null or last_notified_year <> v_year)
      and extract(month from occurs_on)=extract(month from v_today) and extract(day from occurs_on)=extract(day from v_today)
    returning label, kind
  ) select jsonb_agg(jsonb_build_object('label',label,'kind',kind,'partnerUid',v_partner)) from due), '[]'::jsonb);
end; $$;
revoke all on function public.backend_story_claim_due_dates(uuid,uuid) from public, anon, authenticated;
grant execute on function public.backend_story_claim_due_dates(uuid,uuid) to service_role;
