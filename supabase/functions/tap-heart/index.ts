import { body, clients, databaseError, fail, json, preflight, stringValue } from "../_shared/http.ts";
import { notifyPartner } from "../_shared/fcm.ts";

Deno.serve(async (request) => {
  const cors = preflight(request); if (cors) return cors;
  try {
    const input = await body(request);
    const coupleId = stringValue(input.coupleId, "coupleId", 36);
    const tapId = stringValue(input.tapId, "tapId", 36);
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!uuid.test(coupleId) || !uuid.test(tapId)) throw databaseError({ message: "HAKA_INVALID_ARGUMENT" });
    const { user, admin } = await clients(request);
    const { data, error } = await admin.rpc("backend_tap_heart", {
      p_uid: user.id, p_couple_id: coupleId, p_tap_id: tapId,
    });
    if (error) throw databaseError(error);
    const envelope = data as { result: Record<string, unknown>; notifyEligible?: boolean; partnerUid?: string };
    if (envelope.notifyEligible && envelope.partnerUid) {
      try { await notifyPartner(admin, envelope.partnerUid, coupleId); }
      catch (notificationError) { console.warn("Partner notification failed", notificationError); }
    }
    return json(envelope.result);
  } catch (error) { return fail(error); }
});
