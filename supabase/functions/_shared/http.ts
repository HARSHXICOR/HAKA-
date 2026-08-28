import { createClient, type SupabaseClient, type User } from "npm:@supabase/supabase-js@2";

export const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

export function preflight(request: Request): Response | null {
  return request.method === "OPTIONS" ? new Response("ok", { headers: corsHeaders }) : null;
}

export async function body(request: Request): Promise<Record<string, unknown>> {
  if (request.method !== "POST") throw new ApiError(405, "METHOD_NOT_ALLOWED", "POST is required.");
  try {
    const value = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error();
    return value as Record<string, unknown>;
  } catch {
    throw new ApiError(400, "INVALID_ARGUMENT", "A JSON object is required.");
  }
}

export class ApiError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

export async function clients(request: Request): Promise<{
  user: User;
  admin: SupabaseClient;
}> {
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = request.headers.get("authorization");
  if (!url || !anonKey || !serviceKey) throw new ApiError(500, "CONFIGURATION_ERROR", "Backend configuration is incomplete.");
  if (!authorization?.toLowerCase().startsWith("bearer ")) throw new ApiError(401, "UNAUTHENTICATED", "Sign-in is required.");

  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await userClient.auth.getUser(authorization.slice(7));
  if (error || !data.user) throw new ApiError(401, "UNAUTHENTICATED", "The access token is invalid or expired.");

  return {
    user: data.user,
    admin: createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } }),
  };
}

export function databaseError(error: { message?: string } | null): ApiError {
  const message = error?.message ?? "Database operation failed.";
  const mappings: Array<[string, number, string, string]> = [
    ["HAKA_UNAUTHENTICATED", 401, "UNAUTHENTICATED", "Sign-in is required."],
    ["HAKA_PERMISSION_DENIED", 403, "PERMISSION_DENIED", "You are not a member of this couple."],
    ["HAKA_ALREADY_PAIRED", 409, "ALREADY_EXISTS", "You already belong to a couple."],
    ["HAKA_INVALID_TIMEZONE", 400, "INVALID_ARGUMENT", "The timezone is invalid."],
    ["HAKA_INVALID_DISPLAY_NAME", 400, "INVALID_ARGUMENT", "The display name is invalid."],
    ["HAKA_INVALID_INVITE", 400, "INVALID_ARGUMENT", "The invite code is invalid."],
    ["HAKA_SELF_PAIR", 400, "INVALID_ARGUMENT", "You cannot join your own invite."],
    ["HAKA_INVITE_UNAVAILABLE", 409, "FAILED_PRECONDITION", "The invite is invalid, expired, or already redeemed."],
    ["HAKA_COUPLE_FULL", 409, "FAILED_PRECONDITION", "This couple is no longer available."],
    ["HAKA_COUPLE_INCOMPLETE", 409, "FAILED_PRECONDITION", "The couple is not complete."],
    ["HAKA_COUPLE_NOT_FOUND", 404, "NOT_FOUND", "The couple was not found."],
    ["HAKA_RATE_LIMITED", 429, "RESOURCE_EXHAUSTED", "Tap rate limit reached."],
    ["HAKA_THINKING_RATE_LIMITED", 429, "RESOURCE_EXHAUSTED", "Thinking-of-you limit reached. Try again soon."],
    ["HAKA_NOTE_RATE_LIMITED", 429, "RESOURCE_EXHAUSTED", "Love-note limit reached. Try again soon."],
    ["HAKA_INVALID_ARGUMENT", 400, "INVALID_ARGUMENT", "The request is invalid."],
  ];
  for (const [token, status, code, safeMessage] of mappings) {
    if (message.includes(token)) return new ApiError(status, code, safeMessage);
  }
  console.error("database error", message);
  return new ApiError(500, "INTERNAL", "The backend could not complete the request.");
}

export function fail(error: unknown): Response {
  if (error instanceof ApiError) return json({ error: { code: error.code, message: error.message } }, error.status);
  console.error("unhandled error", error);
  return json({ error: { code: "INTERNAL", message: "Unexpected backend error." } }, 500);
}

export function stringValue(value: unknown, name: string, maxLength: number): string {
  if (typeof value !== "string" || value.length === 0 || value.length > maxLength) {
    throw new ApiError(400, "INVALID_ARGUMENT", `${name} is invalid.`);
  }
  return value;
}
