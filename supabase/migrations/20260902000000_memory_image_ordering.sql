create or replace function public.backend_story_update_memory(p_uid uuid,p_couple_id uuid,p_id uuid,p_title text,p_caption text,p_occurred_on date,p_photo_paths jsonb)
returns void language plpgsql security definer set search_path=public,private,pg_catalog as $$ begin
 perform private.require_couple_member(p_uid,p_couple_id);
 if char_length(trim(coalesce(p_title,''))) not between 1 and 80 or char_length(coalesce(p_caption,''))>500 or jsonb_typeof(coalesce(p_photo_paths,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_photo_paths,'[]'::jsonb))>8 then raise exception 'HAKA_INVALID_ARGUMENT'; end if;
 update private.memories set title=trim(p_title),caption=trim(coalesce(p_caption,'')),occurred_on=p_occurred_on,photo_paths=coalesce(p_photo_paths,'[]'::jsonb) where id=p_id and couple_id=p_couple_id;
 if not found then raise exception 'HAKA_NOT_FOUND'; end if;
end; $$;
