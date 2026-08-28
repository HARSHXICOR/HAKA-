do $$
begin
  alter publication supabase_realtime add table public.couple_members;
exception when duplicate_object then null;
end;
$$;

alter table public.couple_members replica identity full;
