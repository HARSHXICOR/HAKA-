import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  RulesTestEnvironment,
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { get, ref, set } from "firebase/database";
import { afterAll, beforeAll, describe, it } from "vitest";

const enabled = process.env.RUN_EMULATOR_TESTS === "1";
const projectId = process.env.GCLOUD_PROJECT ?? "demo-haka";

describe.skipIf(!enabled)("Realtime Database Security Rules", () => {
  let testEnv: RulesTestEnvironment;

  beforeAll(async () => {
    testEnv = await initializeTestEnvironment({
      projectId,
      database: {
        host: "127.0.0.1",
        port: 9100,
        rules: readFileSync(resolve(process.cwd(), "../database.rules.json"), "utf8"),
      },
    });
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await set(ref(context.database()), {
        users: {
          userA: { displayName: "A", coupleId: "coupleA", createdAt: 1 },
          userB: { displayName: "B", coupleId: "coupleA", createdAt: 1 },
          userC: { displayName: "C", coupleId: "coupleC", createdAt: 1 },
        },
        couples: {
          coupleA: {
            members: { userA: "owner", userB: "partner" },
            state: {
              heart: { score: 9_000, maxScore: 10_000, totalTaps: 4, lastUpdatedAt: 1 },
              today: { date: "2026-08-22", tapsByUser: { userA: 2, userB: 2 }, totalTaps: 4, completed: true },
              streak: { current: 1, longest: 1, lastCompletedDate: "2026-08-22" },
              internal: { recentTapIds: { secretTap: { uid: "userA", acceptedAt: 1, expiresAt: 2 } } },
            },
            daily: { "2026-08-22": { totalTaps: 4, completed: true } },
          },
        },
      });
    });
  });

  afterAll(async () => {
    await testEnv?.cleanup();
  });

  it("allows both members to read public state", async () => {
    const userA = testEnv.authenticatedContext("userA").database();
    const userB = testEnv.authenticatedContext("userB").database();
    await assertSucceeds(get(ref(userA, "couples/coupleA/state/heart")));
    await assertSucceeds(get(ref(userB, "couples/coupleA/state/today")));
    await assertSucceeds(get(ref(userA, "couples/coupleA/daily/2026-08-22")));
  });

  it("denies another user and unauthenticated clients", async () => {
    const userC = testEnv.authenticatedContext("userC").database();
    const anonymous = testEnv.unauthenticatedContext().database();
    await assertFails(get(ref(userC, "couples/coupleA/state/heart")));
    await assertFails(get(ref(anonymous, "couples/coupleA/state/heart")));
  });

  it("denies internal ledger reads and authoritative client writes", async () => {
    const userA = testEnv.authenticatedContext("userA").database();
    await assertFails(get(ref(userA, "couples/coupleA/state/internal")));
    await assertFails(set(ref(userA, "couples/coupleA/state/heart/score"), 10_000));
    await assertFails(set(ref(userA, "couples/coupleA/members/userC"), "partner"));
    await assertFails(set(ref(userA, "users/userA/coupleId"), "coupleC"));
  });

  it("allows only the owner to update a valid display name", async () => {
    const userA = testEnv.authenticatedContext("userA").database();
    const userB = testEnv.authenticatedContext("userB").database();
    await assertSucceeds(set(ref(userA, "users/userA/displayName"), "Haka"));
    await assertFails(set(ref(userB, "users/userA/displayName"), "Impersonated"));
  });
});
