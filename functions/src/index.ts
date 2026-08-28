import { getApps, initializeApp } from "firebase-admin/app";
import { getDatabase } from "firebase-admin/database";
import { getMessaging } from "firebase-admin/messaging";
import { randomBytes } from "node:crypto";
import { logger } from "firebase-functions";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { buildCleanupUpdates } from "./domain/cleanup.js";
import { acceptTap, MAX_SCORE, percentage } from "./domain/heart.js";
import { completeDay, resetStreakForNewDay } from "./domain/streak.js";

if (getApps().length === 0) initializeApp();

const db = getDatabase();
const messaging = getMessaging();
const FUNCTIONS_REGION = "asia-south1";
const APP_CHECK_ENFORCED = process.env.FUNCTIONS_EMULATOR !== "true";
const CALLABLE_OPTIONS = {
  region: FUNCTIONS_REGION,
  enforceAppCheck: APP_CHECK_ENFORCED,
  memory: "256MiB" as const,
  timeoutSeconds: 15,
  minInstances: 0,
  maxInstances: 2,
};

type MemberRole = "owner" | "partner";
type Members = Record<string, MemberRole>;

interface TodayState {
  date: string;
  tapsByUser: Record<string, number>;
  totalTaps: number;
  completed: boolean;
  completedAt: number | null;
}

interface CoupleState {
  heart: ReturnType<typeof acceptTap>;
  today: TodayState;
  streak: {
    current: number;
    longest: number;
    lastCompletedDate: string | null;
  };
  internal?: {
    recentTapIds?: Record<string, { uid: string; acceptedAt: number; expiresAt: number }>;
  };
}

function requireAuth(request: { auth?: { uid: string } | null; app?: unknown }): string {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign-in is required.");
  if (APP_CHECK_ENFORCED && !request.app) {
    throw new HttpsError("failed-precondition", "App verification is required.");
  }
  return request.auth.uid;
}

function assertString(value: unknown, name: string, maxLength: number): string {
  if (typeof value !== "string" || value.length === 0 || value.length > maxLength) {
    throw new HttpsError("invalid-argument", `${name} is invalid.`);
  }
  return value;
}

function assertTimezone(value: unknown): string {
  const timezone = assertString(value, "timezone", 64);
  try {
    new Intl.DateTimeFormat("en", { timeZone: timezone }).format();
  } catch {
    throw new HttpsError("invalid-argument", "timezone is invalid.");
  }
  return timezone;
}

function assertInviteCode(value: unknown): string {
  const code = assertString(value, "code", 9).toUpperCase();
  if (!/^[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(code)) {
    throw new HttpsError("invalid-argument", "code is invalid.");
  }
  return code;
}

function assertTapId(value: unknown): string {
  const tapId = assertString(value, "tapId", 36);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(tapId)) {
    throw new HttpsError("invalid-argument", "tapId is invalid.");
  }
  return tapId;
}

function inviteCode(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const value = Array.from(randomBytes(8), (byte) => alphabet[byte % alphabet.length]).join("");
  return `${value.slice(0, 4)}-${value.slice(4)}`;
}

function dateKeyForTimezone(nowSeconds: number, timezone: string): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date(nowSeconds * 1000));
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

function initialState(nowSeconds: number, date: string): CoupleState {
  return {
    heart: {
      score: MAX_SCORE,
      maxScore: MAX_SCORE,
      totalTaps: 0,
      lastUpdatedAt: nowSeconds,
      lastTapAt: null,
    },
    today: { date, tapsByUser: {}, totalTaps: 0, completed: false, completedAt: null },
    streak: { current: 0, longest: 0, lastCompletedDate: null },
    internal: { recentTapIds: {} },
  };
}

function validateMembers(members: Members | null | undefined): string[] {
  const ids = Object.keys(members ?? {});
  if (ids.length !== 2) throw new HttpsError("failed-precondition", "The couple is not complete.");
  return ids;
}

function rollDay(state: CoupleState, newDate: string): void {
  resetStreakForNewDay(state.streak, state.today, newDate);
  state.today = { date: newDate, tapsByUser: {}, totalTaps: 0, completed: false, completedAt: null };
}

export const createCouple = onCall(CALLABLE_OPTIONS, async (request) => {
  const uid = requireAuth(request);
  const timezone = assertTimezone(request.data?.timezone);
  const displayName = typeof request.data?.displayName === "string" ? request.data.displayName.slice(0, 40) : "";
  const userRef = db.ref(`users/${uid}`);
  const user = (await userRef.get()).val() as { coupleId?: string | null; createdAt?: number } | null;
  if (user?.coupleId) throw new HttpsError("already-exists", "You already belong to a couple.");

  const coupleRef = db.ref("couples").push();
  const coupleId = coupleRef.key;
  if (!coupleId) throw new HttpsError("internal", "Could not create couple.");
  const code = inviteCode();
  const now = Math.floor(Date.now() / 1000);
  const invite = { coupleId, creatorUid: uid, expiresAt: now + 900, status: "pending", redeemedBy: null, redeemedAt: null };
  const updates: Record<string, unknown> = {
    [`couples/${coupleId}/members/${uid}`]: "owner",
    [`couples/${coupleId}/timezone`]: timezone,
    [`couples/${coupleId}/status`]: "active",
    [`couples/${coupleId}/createdAt`]: now,
    [`couples/${coupleId}/state`]: initialState(now, dateKeyForTimezone(now, timezone)),
    [`inviteCodes/${code}`]: invite,
    [`users/${uid}/coupleId`]: coupleId,
    [`users/${uid}/createdAt`]: user?.createdAt ?? now,
    ...(displayName ? { [`users/${uid}/displayName`]: displayName } : {}),
  };
  await db.ref().update(updates);
  return { coupleId, inviteCode: code, expiresAt: invite.expiresAt };
});

export const redeemInvite = onCall(CALLABLE_OPTIONS, async (request) => {
  const uid = requireAuth(request);
  const code = assertInviteCode(request.data?.code);
  const userRef = db.ref(`users/${uid}`);
  const user = (await userRef.get()).val() as { coupleId?: string | null } | null;
  if (user?.coupleId) throw new HttpsError("already-exists", "You already belong to a couple.");

  const inviteRef = db.ref(`inviteCodes/${code}`);
  type Invite = { coupleId: string; creatorUid: string; expiresAt: number; status: string; redeemedBy?: string | null; redeemedAt?: number | null };
  const now = Math.floor(Date.now() / 1000);
  const preflight = (await inviteRef.get()).val() as Invite | null;
  if (!preflight || preflight.status !== "pending" || preflight.expiresAt <= now) {
    throw new HttpsError("failed-precondition", "Invite is invalid, expired, or already redeemed.");
  }
  if (preflight.creatorUid === uid) {
    throw new HttpsError("invalid-argument", "You cannot join your own invite.");
  }
  const claim = await inviteRef.transaction((raw) => {
    const current = (raw as Invite | null) ?? preflight;
    if (current.status !== "pending" || current.expiresAt <= now) return;
    return { ...current, status: "redeemed", redeemedBy: uid, redeemedAt: now };
  }, undefined, false);
  const invite = claim.committed ? claim.snapshot.val() as Invite : null;
  if (!invite) throw new HttpsError("failed-precondition", "Invite is invalid, expired, or already redeemed.");

  const coupleRef = db.ref(`couples/${invite.coupleId}`);
  const couple = (await coupleRef.get()).val() as { members?: Members } | null;
  const members = Object.keys(couple?.members ?? {});
  if (members.length !== 1 || members[0] !== invite.creatorUid) {
    await inviteRef.update({ status: "pending", redeemedBy: null, redeemedAt: null });
    throw new HttpsError("failed-precondition", "This couple is no longer available.");
  }
  await db.ref().update({
    [`couples/${invite.coupleId}/members/${uid}`]: "partner",
    [`users/${uid}/coupleId`]: invite.coupleId,
  });
  return { coupleId: invite.coupleId };
});

export const getBootstrap = onCall(CALLABLE_OPTIONS, async (request) => {
  const uid = requireAuth(request);
  const user = (await db.ref(`users/${uid}`).get()).val() as {
    displayName?: string;
    coupleId?: string | null;
    createdAt?: number;
  } | null;
  if (!user?.coupleId) {
    return {
      uid,
      user: user ?? null,
      couple: null,
    };
  }

  const couple = (await db.ref(`couples/${user.coupleId}`).get()).val() as {
    members?: Members;
    timezone?: string;
    status?: string;
    createdAt?: number;
    state?: CoupleState;
  } | null;
  if (!couple?.members?.[uid]) {
    logger.error("user references a couple without membership", { uid, coupleId: user.coupleId });
    throw new HttpsError("failed-precondition", "Account membership is inconsistent.");
  }

  return {
    uid,
    user,
    couple: {
      coupleId: user.coupleId,
      members: couple.members,
      timezone: couple.timezone ?? "UTC",
      status: couple.status ?? "active",
      createdAt: couple.createdAt ?? null,
      state: {
        heart: couple.state?.heart ?? null,
        today: couple.state?.today ?? null,
        streak: couple.state?.streak ?? null,
      },
    },
  };
});

export const tapHeart = onCall(CALLABLE_OPTIONS, async (request) => {
  const uid = requireAuth(request);
  const coupleId = assertString(request.data?.coupleId, "coupleId", 128);
  const tapId = assertTapId(request.data?.tapId);
  const coupleRef = db.ref(`couples/${coupleId}`);
  const snapshot = await coupleRef.get();
  const couple = snapshot.val() as { members?: Members; timezone?: string; state?: CoupleState } | null;
  const members = validateMembers(couple?.members);
  if (!members.includes(uid)) throw new HttpsError("permission-denied", "You are not a member of this couple.");
  if (!couple?.state) throw new HttpsError("failed-precondition", "Couple state is missing.");

  const now = Math.floor(Date.now() / 1000);
  const timezone = couple.timezone ?? "UTC";
  const currentDate = dateKeyForTimezone(now, timezone);
  const stateRef = coupleRef.child("state");
  const preflightState = couple.state;
  let result: { duplicate: boolean; state: CoupleState; rateLimited?: boolean } | undefined;
  logger.info("tap state transaction starting", { coupleId, uid, tapId });
  await stateRef.transaction((raw) => {
    const state = structuredClone((raw as CoupleState | null) ?? preflightState);
    const existing = state.internal?.recentTapIds?.[tapId];
    if (existing) {
      result = { duplicate: true, state };
      return state;
    }
    const recent = Object.values(state.internal?.recentTapIds ?? {}).filter((tap) => tap.acceptedAt >= now - 1);
    if (recent.filter((tap) => tap.uid === uid).length >= 20 || recent.length >= 50) {
      result = { duplicate: false, rateLimited: true, state };
      return state;
    }
    if (state.today.date !== currentDate) rollDay(state, currentDate);
    const next = acceptTap(state.heart, now);
    state.heart = next;
    state.today.tapsByUser ??= {};
    state.today.tapsByUser[uid] = (state.today.tapsByUser[uid] ?? 0) + 1;
    state.today.totalTaps += 1;
    if (members.every((member) => (state.today.tapsByUser[member] ?? 0) > 0)) {
      completeDay(state.streak, state.today, now);
    }
    state.internal ??= {};
    state.internal.recentTapIds ??= {};
    state.internal.recentTapIds[tapId] = { uid, acceptedAt: now, expiresAt: now + 7 * 86400 };
    result = { duplicate: false, state };
    return state;
  }, undefined, false);
  logger.info("tap state transaction finished", { coupleId, uid, tapId, hasResult: Boolean(result) });
  if (!result) throw new HttpsError("aborted", "Tap transaction did not complete.");
  if (result.rateLimited) throw new HttpsError("resource-exhausted", "Tap rate limit reached.");

  const state = result.state;
  const dailyPath = `couples/${coupleId}/daily/${state.today.date}`;
  logger.info("tap daily projection starting", { coupleId, uid, tapId, dailyPath });
  await db.ref().update({
    [`${dailyPath}/tapsByUser`]: state.today.tapsByUser,
    [`${dailyPath}/totalTaps`]: state.today.totalTaps,
    [`${dailyPath}/completed`]: state.today.completed,
    [`${dailyPath}/completedAt`]: state.today.completedAt ?? null,
  });
  logger.info("tap daily projection finished", { coupleId, uid, tapId });
  if (!result.duplicate) {
    try {
      await notifyPartnerOfTap(coupleId, uid, members, now);
    } catch (error) {
      logger.warn("partner notification pipeline failed", { coupleId, error });
    }
  }
  const myTaps = state.today.tapsByUser[uid] ?? 0;
  const partnerTaps = members.filter((member) => member !== uid).reduce((sum, member) => sum + (state.today.tapsByUser[member] ?? 0), 0);
  logger.info("tap processed", { coupleId, uid, tapId, duplicate: result.duplicate });
  return {
    accepted: true,
    duplicate: result.duplicate,
    score: state.heart.score,
    percentage: percentage(state.heart.score),
    totalTaps: state.heart.totalTaps,
    today: { myTaps, partnerTaps, totalTaps: state.today.totalTaps, completed: state.today.completed },
    streak: state.streak,
  };
});

async function notifyPartnerOfTap(coupleId: string, uid: string, members: string[], now: number): Promise<void> {
  const partnerUid = members.find((member) => member !== uid);
  if (!partnerUid) return;
  const throttleRef = db.ref(`couples/${coupleId}/internal/notificationState/${partnerUid}/lastPartnerTapAt`);
  const throttle = await throttleRef.transaction((last) => {
    if (typeof last === "number" && now - last < 300) return;
    return now;
  });
  if (!throttle.committed || throttle.snapshot.val() !== now) return;
  const devices = (await db.ref(`devices/${partnerUid}`).get()).val() as Record<string, { fcmToken?: string; notificationsEnabled?: boolean }> | null;
  const tokens = Object.values(devices ?? {}).filter((device) => device.notificationsEnabled && device.fcmToken).map((device) => device.fcmToken as string);
  if (tokens.length === 0) return;
  try {
    await messaging.sendEachForMulticast({
      tokens,
      notification: { title: "Shared Heart", body: "Your partner added to your heart." },
      data: { type: "partner_tap", coupleId },
    });
  } catch (error) {
    logger.warn("partner notification failed", { coupleId, partnerUid, error });
  }
}

export const cleanupExpiredData = onSchedule({
  schedule: "every 24 hours",
  timeZone: "UTC",
  region: FUNCTIONS_REGION,
  memory: "256MiB",
  timeoutSeconds: 60,
  maxInstances: 1,
}, async () => {
  const now = Math.floor(Date.now() / 1000);
  const invites = (await db.ref("inviteCodes").get()).val() as Record<string, { expiresAt?: number; status?: string }> | null;
  const couples = (await db.ref("couples").get()).val() as Record<string, { state?: { internal?: { recentTapIds?: Record<string, { expiresAt?: number }> } } }> | null;
  const updates = buildCleanupUpdates(invites, couples, now);
  if (Object.keys(updates).length > 0) await db.ref().update(updates);
  logger.info("expired data cleanup completed", { updates: Object.keys(updates).length });
});
