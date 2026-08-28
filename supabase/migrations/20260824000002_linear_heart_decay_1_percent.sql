-- Change the deployed state machine without recreating tables or resetting data.
-- New invariant: 100 points (1%) every completed 30 seconds.
-- A tap adds 25 points and does not reset the decay boundary.
do $$
declare
  v_definition text;
begin
  select pg_get_functiondef('public.backend_get_bootstrap(uuid)'::regprocedure) into v_definition;
  v_definition := replace(v_definition, '/ 1800)::bigint', '/ 30)::bigint');
  v_definition := replace(v_definition, '(v_intervals * 500)::integer', '(v_intervals * 100)::integer');
  v_definition := replace(v_definition, 'interval ''30 minutes''', 'interval ''30 seconds''');
  execute v_definition;

  select pg_get_functiondef('public.backend_tap_heart(uuid, uuid, uuid)'::regprocedure) into v_definition;
  v_definition := replace(v_definition, '/ 1800)::bigint', '/ 30)::bigint');
  v_definition := replace(v_definition, '(v_intervals * 500)::integer', '(v_intervals * 100)::integer');
  v_definition := replace(v_definition, 'last_updated_at = v_now', 'last_updated_at = last_updated_at + (v_intervals * interval ''30 seconds'')');
  execute v_definition;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.couple_members;
exception when duplicate_object then null;
end;
$$;

alter table public.couple_members replica identity full;
