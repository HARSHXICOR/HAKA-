create or replace function private.roll_to_day(p_couple_id uuid, p_day date, p_now timestamptz)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_last date;
begin
  -- p_now is intentionally part of the stable state-machine signature for future audit metadata.
  perform p_now;
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
