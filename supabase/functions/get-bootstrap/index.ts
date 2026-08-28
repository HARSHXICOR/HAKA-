import { clients, databaseError, fail, json, preflight } from "../_shared/http.ts";

Deno.serve(async (request) => {
  const cors = preflight(request); if (cors) return cors;
  try {
    if (request.method !== "POST") return json({ error: { code: "METHOD_NOT_ALLOWED", message: "POST is required." } }, 405);
    const { user, admin } = await clients(request);
    const { data, error } = await admin.rpc("backend_get_bootstrap", { p_uid: user.id });
    if (error) throw databaseError(error);
    return json(data);
  } catch (error) { return fail(error); }
});
