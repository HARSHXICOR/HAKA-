export const MAX_SCORE = 10_000;
export const DECAY_INTERVAL_SECONDS = 1_800;
export const DECAY_AMOUNT = 500;
export const TAP_AMOUNT = 25;

export interface HeartState {
  score: number;
  maxScore: number;
  totalTaps: number;
  lastUpdatedAt: number;
  lastTapAt: number | null;
}

export function clampScore(score: number, maxScore = MAX_SCORE): number {
  return Math.max(0, Math.min(maxScore, Math.trunc(score)));
}

export function materializeDecay(
  heart: HeartState,
  nowSeconds: number,
): HeartState {
  const elapsed = Math.max(0, Math.trunc(nowSeconds - heart.lastUpdatedAt));
  const intervals = Math.floor(elapsed / DECAY_INTERVAL_SECONDS);
  if (intervals === 0) return heart;

  return {
    ...heart,
    score: clampScore(heart.score - intervals * DECAY_AMOUNT, heart.maxScore),
    lastUpdatedAt: heart.lastUpdatedAt + intervals * DECAY_INTERVAL_SECONDS,
  };
}

export function acceptTap(heart: HeartState, nowSeconds: number): HeartState {
  const decayed = materializeDecay(heart, nowSeconds);
  return {
    ...decayed,
    score: clampScore(decayed.score + TAP_AMOUNT, decayed.maxScore),
    totalTaps: decayed.totalTaps + 1,
    lastTapAt: nowSeconds,
    lastUpdatedAt: nowSeconds,
  };
}

export function percentage(score: number, maxScore = MAX_SCORE): number {
  return Math.round((score / maxScore) * 10000) / 100;
}
