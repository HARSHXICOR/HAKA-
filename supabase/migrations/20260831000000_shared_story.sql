-- Shared couple story: memories, future plans, and important dates.
create table if not exists private.memories (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  author_uid uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 80),
  caption text not null default '' check (char_length(caption) <= 500),
  occurred_on date,
  photo_path text,
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists memories_couple_date_idx on private.memories(couple_id, occurred_on desc nulls last, created_at desc);

create table if not exists private.bucket_items (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  author_uid uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 140),
  completed_at timestamptz,
  completed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists bucket_items_couple_idx on private.bucket_items(couple_id, completed_at nulls first, created_at desc);

create table if not exists private.relationship_dates (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  author_uid uuid not null references auth.users(id) on delete cascade,
  label text not null check (char_length(trim(label)) between 1 and 80),
  kind text not null check (kind in ('anniversary', 'birthday', 'custom')),
  occurs_on date not null,
  remind_annually boolean not null default true,
  last_notified_year integer,
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists relationship_dates_couple_date_idx on private.relationship_dates(couple_id, occurs_on);

create or replace function private.require_couple_member(p_uid uuid, p_couple_id uuid)
returns void language plpgsql security definer set search_path = public, private, pg_catalog as $$
begin
  if p_uid is null or p_couple_id is null then raise exception 'HAKA_INVALID_ARGUMENT'; end if;
  if not exists (select 1 from public.couple_members where couple_id = p_couple_id and user_id = p_uid) then
    raise exception 'HAKA_PERMISSION_DENIED';
  end if;
end; $$;

create or replace function public.backend_story_list(p_uid uuid, p_couple_id uuid)
returns jsonb language plpgsql security definer set search_path = public, private, pg_catalog as $$
begin
  perform private.require_couple_member(p_uid, p_couple_id);
  return jsonb_build_object(
    'memories', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'caption',caption,'occurredOn',occurred_on,'photoPath',photo_path,'createdAt',extract(epoch from created_at)::bigint) order by occurred_on desc nulls last, created_at desc) from (select * from private.memories where couple_id=p_couple_id order by occurred_on desc nulls last, created_at desc limit 50) x), '[]'::jsonb),
    'bucketItems', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'completedAt',case when completed_at is null then null else extract(epoch from completed_at)::bigint end,'createdAt',extract(epoch from created_at)::bigint) order by completed_at nulls first, created_at desc) from private.bucket_items where couple_id=p_couple_id), '[]'::jsonb),
    'dates', coalesce((select jsonb_agg(jsonb_build_object('id',id,'label',label,'kind',kind,'occursOn',occurs_on,'remindAnnually',remind_annually) order by extract(month from occurs_on), extract(day from occurs_on)) from private.relationship_dates where couple_id=p_couple_id), '[]'::jsonb)
  );
end; $$;

create or replace function public.backend_story_add_memory(p_uid uuid, p_couple_id uuid, p_title text, p_caption text, p_occurred_on date, p_photo_path text)
returns void language plpgsql security definer set search_path = public, private, pg_catalog as $$
begin perform private.require_couple_member(p_uid,p_couple_id);
  if char_length(trim(coalesce(p_title,''))) not between 1 and 80 or char_length(coalesce(p_caption,'')) > 500 then raise exception 'HAKA_INVALID_ARGUMENT'; end if;
  insert into private.memories(couple_id,author_uid,title,caption,occurred_on,photo_path) values(p_couple_id,p_uid,trim(p_title),trim(coalesce(p_caption,'')),p_occurred_on,nullif(trim(coalesce(p_photo_path,'')),''));
end; $$;

create or replace function public.backend_story_add_bucket(p_uid uuid, p_couple_id uuid, p_title text)
returns void language plpgsql security definer set search_path = public, private, pg_catalog as $$
begin perform private.require_couple_member(p_uid,p_couple_id); if char_length(trim(coalesce(p_title,''))) not between 1 and 140 then raise exception 'HAKA_INVALID_ARGUMENT'; end if; insert into private.bucket_items(couple_id,author_uid,title) values(p_couple_id,p_uid,trim(p_title)); end; $$;

create or replace function public.backend_story_toggle_bucket(p_uid uuid, p_couple_id uuid, p_item_id uuid)
returns void language plpgsql security definer set search_path = public, private, pg_catalog as $$
begin perform private.require_couple_member(p_uid,p_couple_id); update private.bucket_items set completed_at=case when completed_at is null then clock_timestamp() else null end, completed_by=case when completed_at is null then p_uid else null end where id=p_item_id and couple_id=p_couple_id; if not found then raise exception 'HAKA_NOT_FOUND'; end if; end; $$;

create or replace function public.backend_story_add_date(p_uid uuid, p_couple_id uuid, p_label text, p_kind text, p_occurs_on date, p_remind_annually boolean)
returns void language plpgsql security definer set search_path = public, private, pg_catalog as $$
begin perform private.require_couple_member(p_uid,p_couple_id); if char_length(trim(coalesce(p_label,''))) not between 1 and 80 or p_kind not in ('anniversary','birthday','custom') or p_occurs_on is null then raise exception 'HAKA_INVALID_ARGUMENT'; end if; insert into private.relationship_dates(couple_id,author_uid,label,kind,occurs_on,remind_annually) values(p_couple_id,p_uid,trim(p_label),p_kind,p_occurs_on,coalesce(p_remind_annually,true)); end; $$;

revoke all on function public.backend_story_list(uuid,uuid), public.backend_story_add_memory(uuid,uuid,text,text,date,text), public.backend_story_add_bucket(uuid,uuid,text), public.backend_story_toggle_bucket(uuid,uuid,uuid), public.backend_story_add_date(uuid,uuid,text,text,date,boolean) from public, anon, authenticated;
grant execute on function public.backend_story_list(uuid,uuid), public.backend_story_add_memory(uuid,uuid,text,text,date,text), public.backend_story_add_bucket(uuid,uuid,text), public.backend_story_toggle_bucket(uuid,uuid,uuid), public.backend_story_add_date(uuid,uuid,text,text,date,boolean) to service_role;
