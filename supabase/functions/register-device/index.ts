import { ApiError, body, clients, fail, json, preflight, stringValue } from "../_shared/http.ts";

Deno.serve(async (request) => {
  const cors = preflight(request); if (cors) return cors;
  try {
    const input = await body(request);
    const deviceId = stringValue(input.deviceId, "deviceId", 128);
    const fcmToken = stringValue(input.fcmToken, "fcmToken", 4096);
    if (typeof input.notificationsEnabled !== "boolean") {
      throw new ApiError(400, "INVALID_ARGUMENT", "notificationsEnabled is invalid.");
    }
    const { user, admin } = await clients(request);
    const { error } = await admin.from("devices").upsert({
      user_id: user.id,
      device_id: deviceId,
      fcm_token: fcmToken,
      notifications_enabled: input.notificationsEnabled,
      updated_at: new Date().toISOString(),
    });
    if (error) throw error;
    return json({ registered: true });
  } catch (error) { return fail(error); }
});
