import { body, clients, databaseError, fail, json, preflight, stringValue } from "../_shared/http.ts";
import { notifyThinkingOfYou } from "../_shared/fcm.ts";

Deno.serve(async (request) => {
  const cors = preflight(request); if (cors) return cors;
  try {
    const input = await body(request);
    const coupleId = stringValue(input.coupleId, "coupleId", 36);
    const eventId = stringValue(input.eventId, "eventId", 36);
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!uuid.test(coupleId) || !uuid.test(eventId)) throw databaseError({ message: "HAKA_INVALID_ARGUMENT" });
    const { user, admin } = await clients(request);
    const { data, error } = await admin.rpc("backend_thinking_of_you", {
      p_uid: user.id, p_couple_id: coupleId, p_event_id: eventId,
    });
    if (error) throw databaseError(error);
    const envelope = data as { accepted: boolean; duplicate: boolean; eventId: string; partnerUid?: string };
    let notificationSent = false;
    if (envelope.accepted && envelope.partnerUid) {
      try { notificationSent = await notifyThinkingOfYou(admin, envelope.partnerUid, coupleId, envelope.eventId); }
      catch (notificationError) { console.warn("Thinking-of-you notification failed", notificationError); }
    }
    return json({ accepted: envelope.accepted, duplicate: envelope.duplicate, eventId: envelope.eventId, notificationSent });
  } catch (error) { return fail(error); }
});
