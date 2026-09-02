import { body, clients, databaseError, fail, json, preflight, stringValue } from "../_shared/http.ts";
import { notifyRelationshipDate } from "../_shared/fcm.ts";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const date = (value: unknown) => {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value ? null : value;
};
async function uploadPhotos(admin: Awaited<ReturnType<typeof clients>>["admin"], coupleId: string, value: unknown): Promise<string[]> {
  const images = Array.isArray(value) ? value : [];
  if (images.length > 8 || images.some((image) => typeof image !== "string" || image.length > 2_800_000)) throw databaseError({ message: "HAKA_INVALID_ARGUMENT" });
  return Promise.all(images.map(async (base64) => {
    const bytes = Uint8Array.from(atob(base64 as string), (c) => c.charCodeAt(0)); if (bytes.length > 2_097_152) throw databaseError({ message: "HAKA_INVALID_ARGUMENT" });
    const path = `${coupleId}/${crypto.randomUUID()}.jpg`; const result = await admin.storage.from("relationship-media").upload(path, bytes, { contentType: "image/jpeg", upsert: false });
    if (result.error) throw databaseError(result.error); return path;
  }));
}

Deno.serve(async (request) => {
  const cors = preflight(request); if (cors) return cors;
  try {
    const input = await body(request); const coupleId = stringValue(input.coupleId, "coupleId", 36);
    if (!uuid.test(coupleId)) throw databaseError({ message: "HAKA_INVALID_ARGUMENT" });
    const { user, admin } = await clients(request); const action = stringValue(input.action, "action", 24);
    let data: unknown; let error: { message?: string } | null;
    if (action === "list") {
      ({ data, error } = await admin.rpc("backend_story_list", { p_uid:user.id,p_couple_id:coupleId }));
      if (!error && data && typeof data === "object") {
        const story = data as { memories?: Array<Record<string, unknown>> };
        story.memories = await Promise.all((story.memories ?? []).map(async (memory) => {
          const paths = Array.isArray(memory.photoPaths) ? memory.photoPaths.filter((path): path is string => typeof path === "string") : [];
          const signed = await Promise.all(paths.map(async (path) => (await admin.storage.from("relationship-media").createSignedUrl(path, 60 * 60 * 24 * 365)).data?.signedUrl).filter(Boolean));
          return { ...memory, photoKeys: paths, photoPaths: signed };
        }));
        const { data: dueDates, error: dueError } = await admin.rpc("backend_story_claim_due_dates", { p_uid:user.id, p_couple_id:coupleId });
        if (dueError) console.warn("Could not claim relationship reminders", dueError.message);
        for (const due of (dueDates ?? []) as Array<{ label?: string; partnerUid?: string }>) {
          if (due.label && due.partnerUid) notifyRelationshipDate(admin, due.partnerUid, coupleId, due.label).catch((e) => console.warn("Relationship reminder failed", e));
        }
      }
    }
    else if (action === "addMemory") {
      const paths = await uploadPhotos(admin, coupleId, input.photoBase64s);
      ({ data, error } = await admin.rpc("backend_story_add_memory_v2", { p_uid:user.id,p_couple_id:coupleId,p_title:stringValue(input.title,"title",80),p_caption:typeof input.caption === "string" ? input.caption : "",p_occurred_on:date(input.occurredOn),p_photo_paths:paths }));
    }
    else if (action === "addBucket") ({ data, error } = await admin.rpc("backend_story_add_bucket", { p_uid:user.id,p_couple_id:coupleId,p_title:stringValue(input.title,"title",140) }));
    else if (action === "toggleBucket") ({ data, error } = await admin.rpc("backend_story_toggle_bucket", { p_uid:user.id,p_couple_id:coupleId,p_item_id:stringValue(input.itemId,"itemId",36) }));
    else if (action === "addDate") ({ data, error } = await admin.rpc("backend_story_add_date", { p_uid:user.id,p_couple_id:coupleId,p_label:stringValue(input.label,"label",80),p_kind:stringValue(input.kind,"kind",20),p_occurs_on:date(input.occurredOn),p_remind_annually:input.remindAnnually !== false }));
    else if (action === "updateMemory") { const newPaths = await uploadPhotos(admin,coupleId,input.photoBase64s); const kept = Array.isArray(input.photoPaths) ? input.photoPaths.filter((p): p is string => typeof p === "string" && p.startsWith(`${coupleId}/`)) : []; ({ data,error } = await admin.rpc("backend_story_update_memory", {p_uid:user.id,p_couple_id:coupleId,p_id:stringValue(input.itemId,"itemId",36),p_title:stringValue(input.title,"title",80),p_caption:typeof input.caption === "string"?input.caption:"",p_occurred_on:date(input.occurredOn),p_photo_paths:[...kept,...newPaths]})); }
    else if (action === "deleteMemory") {
      ({ data,error } = await admin.rpc("backend_story_delete_memory", {p_uid:user.id,p_couple_id:coupleId,p_id:stringValue(input.itemId,"itemId",36)}));
      if (!error && Array.isArray(data) && data.length) {
        const paths = data.filter((p): p is string => typeof p === "string" && p.startsWith(`${coupleId}/`));
        if (paths.length) { const removed = await admin.storage.from("relationship-media").remove(paths); if (removed.error) console.warn("Memory media cleanup failed",removed.error.message); }
      }
    }
    else if (action === "updateBucket") ({ data,error } = await admin.rpc("backend_story_update_bucket", {p_uid:user.id,p_couple_id:coupleId,p_id:stringValue(input.itemId,"itemId",36),p_title:stringValue(input.title,"title",140)}));
    else if (action === "deleteBucket") ({ data,error } = await admin.rpc("backend_story_delete_bucket", {p_uid:user.id,p_couple_id:coupleId,p_id:stringValue(input.itemId,"itemId",36)}));
    else if (action === "addBucketList") ({ data,error } = await admin.rpc("backend_story_add_bucket_list", {p_uid:user.id,p_couple_id:coupleId,p_title:stringValue(input.title,"title",80)}));
    else if (action === "addBucketListItem") ({ data,error } = await admin.rpc("backend_story_add_bucket_to_list", {p_uid:user.id,p_couple_id:coupleId,p_list_id:stringValue(input.listId,"listId",36),p_title:stringValue(input.title,"title",140)}));
    else if (action === "updateBucketList") ({ data,error } = await admin.rpc("backend_story_update_bucket_list", {p_uid:user.id,p_couple_id:coupleId,p_id:stringValue(input.listId,"listId",36),p_title:stringValue(input.title,"title",80)}));
    else if (action === "deleteBucketList") ({ data,error } = await admin.rpc("backend_story_delete_bucket_list", {p_uid:user.id,p_couple_id:coupleId,p_id:stringValue(input.listId,"listId",36)}));
    else if (action === "updateDate") ({ data,error } = await admin.rpc("backend_story_update_date", {p_uid:user.id,p_couple_id:coupleId,p_id:stringValue(input.itemId,"itemId",36),p_label:stringValue(input.label,"label",80),p_kind:stringValue(input.kind,"kind",20),p_occurs_on:date(input.occurredOn),p_remind_annually:input.remindAnnually!==false}));
    else if (action === "deleteDate") ({ data,error } = await admin.rpc("backend_story_delete_date", {p_uid:user.id,p_couple_id:coupleId,p_id:stringValue(input.itemId,"itemId",36)}));
    else throw databaseError({ message: "HAKA_INVALID_ARGUMENT" });
    if (error) throw databaseError(error); return json(data ?? { ok:true });
  } catch (error) { return fail(error); }
});
