import { body, clients, databaseError, fail, json, preflight, stringValue } from "../_shared/http.ts";

Deno.serve(async (request) => {
  const cors = preflight(request); if (cors) return cors;
  try {
    const input = await body(request);
    const timezone = stringValue(input.timezone, "timezone", 64);
    const displayName = input.displayName === undefined ? null : stringValue(input.displayName, "displayName", 40);
    const { user, admin } = await clients(request);
    const { data, error } = await admin.rpc("backend_create_couple", {
      p_uid: user.id, p_timezone: timezone, p_display_name: displayName,
    });
    if (error) throw databaseError(error);
    return json(data);
  } catch (error) { return fail(error); }
});
