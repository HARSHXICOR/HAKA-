import { createClient } from "@supabase/supabase-js";
import { randomUUID } from "node:crypto";

const url = process.env.SUPABASE_URL;
const anonKey = process.env.SUPABASE_ANON_KEY;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !anonKey || !serviceRoleKey) {
  throw new Error("SUPABASE_URL, SUPABASE_ANON_KEY, and SUPABASE_SERVICE_ROLE_KEY are required.");
}

const admin = createClient(url, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
});

function client() {
  return createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}

async function anonymous(label) {
  const supabase = client();
  const { data, error } = await supabase.auth.signInAnonymously({ options: { data: { display_name: label } } });
  if (error || !data.user || !data.session) throw error ?? new Error(`Could not create ${label}.`);
  return { supabase, uid: data.user.id };
}

async function invoke(user, name, payload = {}) {
  const { data, error } = await user.supabase.functions.invoke(name, { body: payload });
  if (error) {
    let detail = data;
    try {
      if (!detail && error.context instanceof Response) detail = await error.context.clone().json();
    } catch {
      // Preserve the SDK error when the response has no JSON body.
    }
    throw new Error(`${name}: ${error.message}${detail ? ` ${JSON.stringify(detail)}` : ""}`);
  }
  if (data?.error) throw new Error(`${name}: ${JSON.stringify(data.error)}`);
  return data;
}

async function cleanupSmokeUsers() {
  const { data: profiles, error: profilesError } = await admin.from("profiles").select("id").like("display_name", "Smoke%");
  if (profilesError) throw profilesError;
  const ids = (profiles ?? []).map((profile) => profile.id);
  if (ids.length === 0) return;
  const { data: members, error: membersError } = await admin.from("couple_members").select("couple_id").in("user_id", ids);
  if (membersError) throw membersError;
  const coupleIds = [...new Set((members ?? []).map((member) => member.couple_id))];
  if (coupleIds.length > 0) {
    const { error } = await admin.from("couples").delete().in("id", coupleIds);
    if (error) throw error;
  }
  for (const id of ids) {
    const { error } = await admin.auth.admin.deleteUser(id);
    if (error && !/not found/i.test(error.message)) throw error;
  }
}

await cleanupSmokeUsers();
try {
  const a = await anonymous("Smoke A");
  const b = await anonymous("Smoke B");
  const outsider = await anonymous("Smoke outsider");

  const created = await invoke(a, "create-couple", { displayName: "Smoke A", timezone: "Asia/Kolkata" });
  if (!created.coupleId || !created.inviteCode) throw new Error("create-couple returned an invalid contract.");

  const joined = await invoke(b, "redeem-invite", { code: created.inviteCode });
  if (joined.coupleId !== created.coupleId) throw new Error("redeem-invite joined the wrong couple.");

  const tapId = randomUUID();
  const first = await invoke(a, "tap-heart", { coupleId: created.coupleId, tapId });
  const duplicate = await invoke(a, "tap-heart", { coupleId: created.coupleId, tapId });
  if (!first.accepted || first.duplicate || !duplicate.duplicate || duplicate.totalTaps !== first.totalTaps) {
    throw new Error("Tap idempotency contract failed.");
  }

  const { error: decaySeedError } = await admin.from("heart_state").update({
    score: 8000,
    last_updated_at: new Date(Date.now() - 3_600_000).toISOString(),
  }).eq("couple_id", created.coupleId);
  if (decaySeedError) throw decaySeedError;

  const partner = await invoke(b, "tap-heart", { coupleId: created.coupleId, tapId: randomUUID() });
  if (partner.score !== 7025) throw new Error(`Decay contract failed: expected 7025, received ${partner.score}.`);
  if (!partner.today.completed || partner.streak.current !== 1) throw new Error("Daily completion/streak contract failed.");

  const bootstrap = await invoke(a, "get-bootstrap");
  if (bootstrap.uid !== a.uid || bootstrap.couple?.coupleId !== created.coupleId) {
    throw new Error("get-bootstrap recovery contract failed.");
  }

  let outsiderDenied = false;
  try { await invoke(outsider, "tap-heart", { coupleId: created.coupleId, tapId: randomUUID() }); }
  catch (error) { outsiderDenied = /PERMISSION_DENIED|member/i.test(String(error)); }
  if (!outsiderDenied) throw new Error("Outsider tap was not denied.");

  let forgedDenied = false;
  try { await invoke(a, "tap-heart", { coupleId: created.coupleId, tapId: "forged" }); }
  catch (error) { forgedDenied = /INVALID_ARGUMENT|invalid/i.test(String(error)); }
  if (!forgedDenied) throw new Error("Forged tap ID was not denied.");

  console.log(JSON.stringify({
    ok: true,
    coupleId: created.coupleId,
    checks: ["createCouple", "redeemInvite", "tapHeart", "duplicateTap", "linearDecay", "dailyCompletion", "streak", "getBootstrap", "authorization", "validation"],
    cleanedUp: true,
  }, null, 2));
} finally {
  await cleanupSmokeUsers();
}
