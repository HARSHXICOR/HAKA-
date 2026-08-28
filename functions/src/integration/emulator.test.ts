import { deleteApp, initializeApp } from "firebase-admin/app";
import { getDatabase } from "firebase-admin/database";
import { afterAll, describe, expect, it } from "vitest";

const enabled = process.env.RUN_EMULATOR_TESTS === "1";
const projectId = process.env.GCLOUD_PROJECT ?? "demo-haka";
const functionsBase = `http://127.0.0.1:5101/${projectId}/asia-south1`;
const authBase = "http://127.0.0.1:9199/identitytoolkit.googleapis.com/v1";
const adminApp = enabled ? initializeApp({
  projectId,
  databaseURL: `http://127.0.0.1:9100?ns=${projectId}`,
}, "haka-integration-test") : null;
const adminDatabase = adminApp ? getDatabase(adminApp) : null;

async function createUser(email: string) {
  const response = await fetch(`${authBase}/accounts:signUp?key=demo-api-key`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email, password: "password123", returnSecureToken: true }),
  });
  if (!response.ok) throw new Error(`Auth emulator failed: ${await response.text()}`);
  return await response.json() as { localId: string; idToken: string };
}

async function signInUser(email: string) {
  const response = await fetch(`${authBase}/accounts:signInWithPassword?key=demo-api-key`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email, password: "password123", returnSecureToken: true }),
  });
  if (!response.ok) throw new Error(`Auth emulator sign-in failed: ${await response.text()}`);
  return await response.json() as { localId: string; idToken: string };
}

async function call(name: string, idToken: string, data: unknown) {
  const response = await fetch(`${functionsBase}/${name}`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${idToken}` },
    body: JSON.stringify({ data }),
  });
  const body = await response.json() as { data?: unknown; result?: unknown; error?: unknown };
  if (!response.ok) throw new Error(`${name} failed: ${JSON.stringify(body)}`);
  return (body.result ?? body.data) as Record<string, unknown>;
}

describe.skipIf(!enabled)("Firebase Emulator backend", () => {
  afterAll(async () => {
    if (adminApp) await deleteApp(adminApp);
  });

  it("runs pairing, decay, streak, security, rate limit, idempotency, and recovery", async () => {
    const suffix = `${Date.now()}-${Math.random()}`;
    const emailA = `a-${suffix}@example.test`;
    const userA = await createUser(emailA);
    const userB = await createUser(`b-${suffix}@example.test`);
    const userC = await createUser(`c-${suffix}@example.test`);

    const created = await call("createCouple", userA.idToken, {
      displayName: "A",
      timezone: "UTC",
    });
    const joined = await call("redeemInvite", userB.idToken, { code: created.inviteCode });
    expect(joined.coupleId).toBe(created.coupleId);

    const first = await call("tapHeart", userA.idToken, {
      coupleId: created.coupleId,
      tapId: "00000000-0000-4000-8000-000000000001",
    });
    const duplicate = await call("tapHeart", userA.idToken, {
      coupleId: created.coupleId,
      tapId: "00000000-0000-4000-8000-000000000001",
    });

    expect(first.accepted).toBe(true);
    expect(first.duplicate).toBe(false);
    expect(duplicate.duplicate).toBe(true);
    expect(duplicate.totalTaps).toBe(first.totalTaps);

    const now = Math.floor(Date.now() / 1000);
    await adminDatabase!.ref(`couples/${created.coupleId}/state/heart`).update({
      score: 8_000,
      lastUpdatedAt: now - 3_600,
    });
    const partnerTap = await call("tapHeart", userB.idToken, {
      coupleId: created.coupleId,
      tapId: "00000000-0000-4000-8000-000000000002",
    });
    expect(partnerTap.score).toBe(7_025);
    expect((partnerTap.today as { completed: boolean }).completed).toBe(true);
    expect((partnerTap.streak as { current: number }).current).toBe(1);

    await expect(call("tapHeart", userC.idToken, {
      coupleId: created.coupleId,
      tapId: "00000000-0000-4000-8000-000000000003",
    })).rejects.toThrow(/PERMISSION_DENIED/);
    await expect(call("tapHeart", userA.idToken, {
      coupleId: created.coupleId,
      tapId: "forged",
    })).rejects.toThrow(/INVALID_ARGUMENT/);

    const concurrent = await Promise.all([0, 1].map((index) => call("tapHeart", userA.idToken, {
      coupleId: created.coupleId,
      tapId: `10000000-0000-4000-8000-${String(index + 100).padStart(12, "0")}`,
    })));
    expect(concurrent.every((entry) => entry.accepted === true)).toBe(true);
    expect(Math.max(...concurrent.map((entry) => entry.totalTaps as number))).toBeGreaterThanOrEqual((partnerTap.totalTaps as number) + 2);

    const rateLimitNow = Math.floor(Date.now() / 1000);
    const recentTapIds = Object.fromEntries(Array.from({ length: 20 }, (_, index) => [
      `seed-${index}`,
      { uid: userA.localId, acceptedAt: rateLimitNow, expiresAt: rateLimitNow + 86_400 },
    ]));
    await adminDatabase!.ref(`couples/${created.coupleId}/state/internal/recentTapIds`).set(recentTapIds);
    await expect(call("tapHeart", userA.idToken, {
      coupleId: created.coupleId,
      tapId: "10000000-0000-4000-8000-000000000200",
    })).rejects.toThrow(/RESOURCE_EXHAUSTED/);

    const recoveredUserA = await signInUser(emailA);
    expect(recoveredUserA.localId).toBe(userA.localId);
    const bootstrap = await call("getBootstrap", recoveredUserA.idToken, {});
    expect(bootstrap.uid).toBe(userA.localId);
    expect((bootstrap.couple as { coupleId: string }).coupleId).toBe(created.coupleId);
    expect(((bootstrap.couple as { state: { heart: { totalTaps: number } } }).state.heart).totalTaps).toBeGreaterThanOrEqual(partnerTap.totalTaps as number);
  }, 30_000);

});
