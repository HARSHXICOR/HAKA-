interface InviteRecord {
  expiresAt?: number;
  status?: string;
}

interface CoupleCleanupRecord {
  state?: {
    internal?: {
      recentTapIds?: Record<string, { expiresAt?: number }>;
    };
  };
}

export function buildCleanupUpdates(
  invites: Record<string, InviteRecord> | null,
  couples: Record<string, CoupleCleanupRecord> | null,
  nowSeconds: number,
): Record<string, null | string> {
  const updates: Record<string, null | string> = {};

  for (const [code, invite] of Object.entries(invites ?? {})) {
    if (invite.status === "pending" && typeof invite.expiresAt === "number" && invite.expiresAt <= nowSeconds) {
      updates[`inviteCodes/${code}/status`] = "expired";
    }
    if (invite.status !== "pending" && typeof invite.expiresAt === "number" && invite.expiresAt + 7 * 86_400 <= nowSeconds) {
      updates[`inviteCodes/${code}`] = null;
    }
  }

  for (const [coupleId, couple] of Object.entries(couples ?? {})) {
    for (const [tapId, tap] of Object.entries(couple.state?.internal?.recentTapIds ?? {})) {
      if (typeof tap.expiresAt === "number" && tap.expiresAt <= nowSeconds) {
        updates[`couples/${coupleId}/state/internal/recentTapIds/${tapId}`] = null;
      }
    }
  }

  return updates;
}
