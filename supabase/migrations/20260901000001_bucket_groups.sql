-- Bucket list groups coexist with standalone bucket items. A null list_id means standalone.
create table if not exists private.bucket_lists (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  author_uid uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 80),
  created_at timestamptz not null default clock_timestamp()
);
alter table private.bucket_items add column if not exists list_id uuid references private.bucket_lists(id) on delete cascade;
create index if not exists bucket_lists_couple_idx on private.bucket_lists(couple_id,created_at desc);
create index if not exists bucket_items_list_idx on private.bucket_items(list_id,created_at);

create or replace function public.backend_story_add_bucket_list(p_uid uuid,p_couple_id uuid,p_title text)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$ begin
 perform private.require_couple_member(p_uid,p_couple_id); if char_length(trim(coalesce(p_title,''))) not between 1 and 80 then raise exception 'HAKA_INVALID_ARGUMENT'; end if;
 insert into private.bucket_lists(couple_id,author_uid,title) values(p_couple_id,p_uid,trim(p_title)); end; $$;
create or replace function public.backend_story_add_bucket_to_list(p_uid uuid,p_couple_id uuid,p_list_id uuid,p_title text)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$ begin
 perform private.require_couple_member(p_uid,p_couple_id); if char_length(trim(coalesce(p_title,''))) not between 1 and 140 or not exists(select 1 from private.bucket_lists where id=p_list_id and couple_id=p_couple_id) then raise exception 'HAKA_INVALID_ARGUMENT'; end if;
 insert into private.bucket_items(couple_id,author_uid,list_id,title) values(p_couple_id,p_uid,p_list_id,trim(p_title)); end; $$;
create or replace function public.backend_story_update_bucket_list(p_uid uuid,p_couple_id uuid,p_id uuid,p_title text)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$ begin perform private.require_couple_member(p_uid,p_couple_id); update private.bucket_lists set title=trim(p_title) where id=p_id and couple_id=p_couple_id and char_length(trim(coalesce(p_title,''))) between 1 and 80; if not found then raise exception 'HAKA_INVALID_ARGUMENT'; end if; end; $$;
create or replace function public.backend_story_delete_bucket_list(p_uid uuid,p_couple_id uuid,p_id uuid)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$ begin perform private.require_couple_member(p_uid,p_couple_id); delete from private.bucket_lists where id=p_id and couple_id=p_couple_id; if not found then raise exception 'HAKA_NOT_FOUND'; end if; end; $$;

create or replace function public.backend_story_list(p_uid uuid,p_couple_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_catalog as $$ begin
 perform private.require_couple_member(p_uid,p_couple_id);
 return jsonb_build_object(
 'memories',coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'caption',caption,'occurredOn',occurred_on,'photoPaths',photo_paths,'createdAt',extract(epoch from created_at)::bigint) order by occurred_on desc nulls last,created_at desc) from private.memories where couple_id=p_couple_id),'[]'::jsonb),
 'bucketItems',coalesce((select jsonb_agg(jsonb_build_object('id',id,'listId',list_id,'title',title,'completedAt',case when completed_at is null then null else extract(epoch from completed_at)::bigint end,'createdAt',extract(epoch from created_at)::bigint) order by created_at desc) from private.bucket_items where couple_id=p_couple_id),'[]'::jsonb),
 'bucketLists',coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'createdAt',extract(epoch from created_at)::bigint) order by created_at desc) from private.bucket_lists where couple_id=p_couple_id),'[]'::jsonb),
 'dates',coalesce((select jsonb_agg(jsonb_build_object('id',id,'label',label,'kind',kind,'occursOn',occurs_on,'remindAnnually',remind_annually) order by extract(month from occurs_on),extract(day from occurs_on)) from private.relationship_dates where couple_id=p_couple_id),'[]'::jsonb)); end; $$;
revoke all on function public.backend_story_add_bucket_list(uuid,uuid,text),public.backend_story_add_bucket_to_list(uuid,uuid,uuid,text),public.backend_story_update_bucket_list(uuid,uuid,uuid,text),public.backend_story_delete_bucket_list(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.backend_story_add_bucket_list(uuid,uuid,text),public.backend_story_add_bucket_to_list(uuid,uuid,uuid,text),public.backend_story_update_bucket_list(uuid,uuid,uuid,text),public.backend_story_delete_bucket_list(uuid,uuid,uuid) to service_role;
