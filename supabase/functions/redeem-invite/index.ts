import { body, clients, databaseError, fail, json, preflight, stringValue } from "../_shared/http.ts";

Deno.serve(async (request) => {
  const cors = preflight(request); if (cors) return cors;
  try {
    const input = await body(request);
    const code = stringValue(input.code, "code", 9).toUpperCase();
    if (!/^[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(code)) throw databaseError({ message: "HAKA_INVALID_INVITE" });
    const { user, admin } = await clients(request);
    const { data, error } = await admin.rpc("backend_redeem_invite", { p_uid: user.id, p_code: code });
    if (error) throw databaseError(error);
    return json(data);
  } catch (error) { return fail(error); }
});
