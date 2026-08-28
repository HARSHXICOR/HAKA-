import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
  token_uri?: string;
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function utf8(value: string): Uint8Array {
  return new TextEncoder().encode(value);
}

function pemBytes(pem: string): Uint8Array {
  const raw = atob(pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, ""));
  return Uint8Array.from(raw, (char) => char.charCodeAt(0));
}

async function accessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(utf8(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claim = base64Url(utf8(JSON.stringify({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: account.token_uri ?? "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemBytes(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, utf8(`${header}.${claim}`)));
  const assertion = `${header}.${claim}.${base64Url(signature)}`;
  const response = await fetch(account.token_uri ?? "https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!response.ok) throw new Error(`FCM OAuth failed (${response.status}).`);
  const payload = await response.json() as { access_token?: string };
  if (!payload.access_token) throw new Error("FCM OAuth returned no access token.");
  return payload.access_token;
}

export async function notifyPartner(admin: SupabaseClient, partnerUid: string, coupleId: string): Promise<void> {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!raw) {
    console.error("FCM is not configured: FIREBASE_SERVICE_ACCOUNT_JSON is missing.");
    return;
  }
  const account = JSON.parse(raw) as ServiceAccount;
  const { data, error } = await admin.from("devices")
    .select("fcm_token")
    .eq("user_id", partnerUid)
    .eq("notifications_enabled", true);
  if (error) throw error;
  const tokens = [...new Set((data ?? []).map((entry) => entry.fcm_token as string).filter(Boolean))];
  if (tokens.length === 0) {
    console.warn("FCM tap notification skipped: partner has no enabled device.");
    return;
  }
  const bearer = await accessToken(account);
  await Promise.all(tokens.map(async (token) => {
    const response = await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
      method: "POST",
      headers: { authorization: `Bearer ${bearer}`, "content-type": "application/json" },
      body: JSON.stringify({ message: {
        token,
        notification: { title: "Shared Heart", body: "Your partner added to your heart." },
        data: { type: "partner_tap", coupleId },
      } }),
    });
    if (!response.ok) console.warn("FCM send failed", response.status, await response.text());
  }));
}

export async function notifyThinkingOfYou(admin: SupabaseClient, partnerUid: string, coupleId: string, eventId: string): Promise<boolean> {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!raw) {
    console.error("FCM is not configured: FIREBASE_SERVICE_ACCOUNT_JSON is missing.");
    return false;
  }
  const account = JSON.parse(raw) as ServiceAccount;
  const { data, error } = await admin.from("devices")
    .select("fcm_token")
    .eq("user_id", partnerUid)
    .eq("notifications_enabled", true);
  if (error) throw error;
  const tokens = [...new Set((data ?? []).map((entry) => entry.fcm_token as string).filter(Boolean))];
  if (tokens.length === 0) {
    console.warn("FCM thinking-of-you notification skipped: partner has no enabled device.");
    return false;
  }
  const bearer = await accessToken(account);
  const results = await Promise.all(tokens.map(async (token) => {
    const response = await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
      method: "POST",
      headers: { authorization: `Bearer ${bearer}`, "content-type": "application/json" },
      body: JSON.stringify({ message: {
        token,
        notification: { title: "Thinking of You 💕", body: "Your partner is thinking of you." },
        data: { type: "thinking_of_you", coupleId, eventId },
      } }),
    });
    if (!response.ok) {
      console.warn("FCM thinking-of-you send failed", response.status, await response.text());
      return false;
    }
    return true;
  }));
  if (results.some((sent) => !sent)) {
    console.warn("FCM thinking-of-you delivery was rejected for one or more devices.");
    return false;
  }
  return true;
}

export async function notifyLoveNote(admin: SupabaseClient, partnerUid: string, coupleId: string, noteId: string): Promise<boolean> {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!raw) {
    console.error("FCM is not configured: FIREBASE_SERVICE_ACCOUNT_JSON is missing.");
    return false;
  }
  const account = JSON.parse(raw) as ServiceAccount;
  const { data, error } = await admin.from("devices")
    .select("fcm_token")
    .eq("user_id", partnerUid)
    .eq("notifications_enabled", true);
  if (error) throw error;
  const tokens = [...new Set((data ?? []).map((entry) => entry.fcm_token as string).filter(Boolean))];
  if (tokens.length === 0) {
    console.warn("FCM love-note notification skipped: partner has no enabled device.");
    return false;
  }
  const bearer = await accessToken(account);
  const results = await Promise.all(tokens.map(async (token) => {
    const response = await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
      method: "POST",
      headers: { authorization: `Bearer ${bearer}`, "content-type": "application/json" },
      body: JSON.stringify({ message: {
        token,
        notification: { title: "Love Note 💌", body: "Your partner sent you a private note." },
        data: { type: "love_note", coupleId, noteId },
      } }),
    });
    if (!response.ok) {
      console.warn("FCM love-note send failed", response.status, await response.text());
      return false;
    }
    return true;
  }));
  return results.every(Boolean);
}
