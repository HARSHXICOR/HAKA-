import { describe, expect, it } from "vitest";
import { buildCleanupUpdates } from "./cleanup.js";

describe("expired data cleanup", () => {
  it("expires pending invites and removes old maintenance records", () => {
    const now = 1_000_000;
    const updates = buildCleanupUpdates({
      pending: { status: "pending", expiresAt: now - 1 },
      old: { status: "expired", expiresAt: now - 8 * 86_400 },
      fresh: { status: "redeemed", expiresAt: now - 1 },
    }, {
      coupleA: {
        state: {
          internal: {
            recentTapIds: {
              oldTap: { expiresAt: now - 1 },
              freshTap: { expiresAt: now + 1 },
            },
          },
        },
      },
    }, now);

    expect(updates).toEqual({
      "inviteCodes/pending/status": "expired",
      "inviteCodes/old": null,
      "couples/coupleA/state/internal/recentTapIds/oldTap": null,
    });
  });
});
