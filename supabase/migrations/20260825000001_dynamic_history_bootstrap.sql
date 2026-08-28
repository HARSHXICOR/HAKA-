-- Return real daily summaries with bootstrap so Stats and History never need
-- placeholder chart values. The newest 90 days are enough for the MVP UI.
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
  v_history jsonb := '[]'::jsonb;
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

  select coalesce(jsonb_agg(jsonb_build_object(
      'date', d.day::text,
      'tapsByUser', d.taps_by_user,
      'myTaps', coalesce((d.taps_by_user ->> p_uid::text)::integer, 0),
      'partnerTaps', greatest(0, d.total_taps - coalesce((d.taps_by_user ->> p_uid::text)::integer, 0)),
      'totalTaps', d.total_taps,
      'completed', d.completed,
      'completedAt', case when d.completed_at is null then null else extract(epoch from d.completed_at)::bigint end
    ) order by d.day desc), '[]'::jsonb)
    into v_history
    from (
      select day, taps_by_user, total_taps, completed, completed_at
        from public.daily_stats
       where couple_id = p_couple_id
       order by day desc
       limit 90
    ) d;

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
    ),
    'history', v_history
  );
end;
$$;
