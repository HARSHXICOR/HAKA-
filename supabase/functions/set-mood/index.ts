import { body, clients, databaseError, fail, json, preflight, stringValue } from "../_shared/http.ts";

Deno.serve(async (request) => {
  const cors = preflight(request); if (cors) return cors;
  try {
    const input = await body(request);
    const coupleId = stringValue(input.coupleId, "coupleId", 36);
    const mood = stringValue(input.mood, "mood", 20);
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!uuid.test(coupleId)) throw databaseError({ message: "HAKA_INVALID_ARGUMENT" });
    const { user, admin } = await clients(request);
    const { data, error } = await admin.rpc("backend_set_daily_mood", { p_uid: user.id, p_couple_id: coupleId, p_mood: mood });
    if (error) throw databaseError(error);
    return json(data);
  } catch (error) { return fail(error); }
});
