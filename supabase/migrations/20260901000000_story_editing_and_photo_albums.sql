alter table private.memories add column if not exists photo_paths jsonb not null default '[]'::jsonb;
update private.memories set photo_paths = case when photo_path is null then '[]'::jsonb else jsonb_build_array(photo_path) end where photo_paths = '[]'::jsonb and photo_path is not null;

create or replace function public.backend_story_list(p_uid uuid, p_couple_id uuid)
returns jsonb language plpgsql security definer set search_path = public, private, pg_catalog as $$
begin
  perform private.require_couple_member(p_uid, p_couple_id);
  return jsonb_build_object(
    'memories', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'caption',caption,'occurredOn',occurred_on,'photoPaths',photo_paths,'createdAt',extract(epoch from created_at)::bigint) order by occurred_on desc nulls last, created_at desc) from (select * from private.memories where couple_id=p_couple_id order by occurred_on desc nulls last, created_at desc limit 200) x), '[]'::jsonb),
    'bucketItems', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'completedAt',case when completed_at is null then null else extract(epoch from completed_at)::bigint end,'createdAt',extract(epoch from created_at)::bigint) order by completed_at nulls first, created_at desc) from private.bucket_items where couple_id=p_couple_id), '[]'::jsonb),
    'dates', coalesce((select jsonb_agg(jsonb_build_object('id',id,'label',label,'kind',kind,'occursOn',occurs_on,'remindAnnually',remind_annually) order by extract(month from occurs_on), extract(day from occurs_on)) from private.relationship_dates where couple_id=p_couple_id), '[]'::jsonb)
  );
end; $$;

create or replace function public.backend_story_update_memory(p_uid uuid,p_couple_id uuid,p_id uuid,p_title text,p_caption text,p_occurred_on date,p_photo_paths jsonb)
returns void language plpgsql security definer set search_path = public,private,pg_catalog as $$
begin perform private.require_couple_member(p_uid,p_couple_id); if char_length(trim(coalesce(p_title,''))) not between 1 and 80 or char_length(coalesce(p_caption,''))>500 then raise exception 'HAKA_INVALID_ARGUMENT'; end if;
 update private.memories set title=trim(p_title),caption=trim(coalesce(p_caption,'')),occurred_on=p_occurred_on,photo_paths=coalesce(photo_paths,'[]'::jsonb) || coalesce(p_photo_paths,'[]'::jsonb) where id=p_id and couple_id=p_couple_id; if not found then raise exception 'HAKA_NOT_FOUND'; end if; end; $$;
create or replace function public.backend_story_delete_memory(p_uid uuid,p_couple_id uuid,p_id uuid)
returns jsonb language plpgsql security definer set search_path = public,private,pg_catalog as $$ declare v_paths jsonb;
begin perform private.require_couple_member(p_uid,p_couple_id); delete from private.memories where id=p_id and couple_id=p_couple_id returning photo_paths into v_paths; if not found then raise exception 'HAKA_NOT_FOUND'; end if; return coalesce(v_paths,'[]'::jsonb); end; $$;
create or replace function public.backend_story_update_bucket(p_uid uuid,p_couple_id uuid,p_id uuid,p_title text)
returns void language plpgsql security definer set search_path = public,private,pg_catalog as $$ begin perform private.require_couple_member(p_uid,p_couple_id); if char_length(trim(coalesce(p_title,''))) not between 1 and 140 then raise exception 'HAKA_INVALID_ARGUMENT'; end if; update private.bucket_items set title=trim(p_title) where id=p_id and couple_id=p_couple_id; if not found then raise exception 'HAKA_NOT_FOUND'; end if; end; $$;
create or replace function public.backend_story_delete_bucket(p_uid uuid,p_couple_id uuid,p_id uuid)
returns void language plpgsql security definer set search_path = public,private,pg_catalog as $$ begin perform private.require_couple_member(p_uid,p_couple_id); delete from private.bucket_items where id=p_id and couple_id=p_couple_id; if not found then raise exception 'HAKA_NOT_FOUND'; end if; end; $$;
create or replace function public.backend_story_update_date(p_uid uuid,p_couple_id uuid,p_id uuid,p_label text,p_kind text,p_occurs_on date,p_remind_annually boolean)
returns void language plpgsql security definer set search_path = public,private,pg_catalog as $$ begin perform private.require_couple_member(p_uid,p_couple_id); if char_length(trim(coalesce(p_label,''))) not between 1 and 80 or p_kind not in ('anniversary','birthday','custom') or p_occurs_on is null then raise exception 'HAKA_INVALID_ARGUMENT'; end if; update private.relationship_dates set label=trim(p_label),kind=p_kind,occurs_on=p_occurs_on,remind_annually=coalesce(p_remind_annually,true),last_notified_year=null where id=p_id and couple_id=p_couple_id; if not found then raise exception 'HAKA_NOT_FOUND'; end if; end; $$;
create or replace function public.backend_story_delete_date(p_uid uuid,p_couple_id uuid,p_id uuid)
returns void language plpgsql security definer set search_path = public,private,pg_catalog as $$ begin perform private.require_couple_member(p_uid,p_couple_id); delete from private.relationship_dates where id=p_id and couple_id=p_couple_id; if not found then raise exception 'HAKA_NOT_FOUND'; end if; end; $$;
revoke all on function public.backend_story_update_memory(uuid,uuid,uuid,text,text,date,jsonb),public.backend_story_delete_memory(uuid,uuid,uuid),public.backend_story_update_bucket(uuid,uuid,uuid,text),public.backend_story_delete_bucket(uuid,uuid,uuid),public.backend_story_update_date(uuid,uuid,uuid,text,text,date,boolean),public.backend_story_delete_date(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.backend_story_update_memory(uuid,uuid,uuid,text,text,date,jsonb),public.backend_story_delete_memory(uuid,uuid,uuid),public.backend_story_update_bucket(uuid,uuid,uuid,text),public.backend_story_delete_bucket(uuid,uuid,uuid),public.backend_story_update_date(uuid,uuid,uuid,text,text,date,boolean),public.backend_story_delete_date(uuid,uuid,uuid) to service_role;

create or replace function public.backend_story_add_memory_v2(p_uid uuid,p_couple_id uuid,p_title text,p_caption text,p_occurred_on date,p_photo_paths jsonb)
returns void language plpgsql security definer set search_path = public,private,pg_catalog as $$
begin perform private.require_couple_member(p_uid,p_couple_id); if char_length(trim(coalesce(p_title,''))) not between 1 and 80 or char_length(coalesce(p_caption,''))>500 or jsonb_array_length(coalesce(p_photo_paths,'[]'::jsonb))>8 then raise exception 'HAKA_INVALID_ARGUMENT'; end if;
insert into private.memories(couple_id,author_uid,title,caption,occurred_on,photo_paths) values(p_couple_id,p_uid,trim(p_title),trim(coalesce(p_caption,'')),p_occurred_on,coalesce(p_photo_paths,'[]'::jsonb)); end; $$;
revoke all on function public.backend_story_add_memory_v2(uuid,uuid,text,text,date,jsonb) from public,anon,authenticated;
grant execute on function public.backend_story_add_memory_v2(uuid,uuid,text,text,date,jsonb) to service_role;
