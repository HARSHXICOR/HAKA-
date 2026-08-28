import { body, clients, databaseError, fail, json, preflight, stringValue } from "../_shared/http.ts";
import { notifyLoveNote } from "../_shared/fcm.ts";

Deno.serve(async (request) => {
  const cors = preflight(request); if (cors) return cors;
  try {
    const input = await body(request);
    const coupleId = stringValue(input.coupleId, "coupleId", 36);
    const noteBody = stringValue(input.body, "body", 160);
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!uuid.test(coupleId) || noteBody.trim().length === 0) throw databaseError({ message: "HAKA_INVALID_ARGUMENT" });
    const { user, admin } = await clients(request);
    const { data, error } = await admin.rpc("backend_send_love_note", { p_uid: user.id, p_couple_id: coupleId, p_body: noteBody });
    if (error) throw databaseError(error);
    const note = data as Record<string, unknown> & { partnerUid?: string; id?: string };
    let notificationSent = false;
    if (note.partnerUid && note.id) {
      try { notificationSent = await notifyLoveNote(admin, note.partnerUid, coupleId, note.id); }
      catch (notificationError) { console.warn("Love-note notification failed", notificationError); }
    }
    return json({
      id: note.id,
      coupleId: note.coupleId,
      senderUid: note.senderUid,
      recipientUid: note.recipientUid,
      body: note.body,
      createdAt: note.createdAt,
      readAt: note.readAt ?? null,
      notificationSent,
    });
  } catch (error) { return fail(error); }
});
