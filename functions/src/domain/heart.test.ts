import { describe, expect, it } from "vitest";
import {
  DECAY_AMOUNT,
  DECAY_INTERVAL_SECONDS,
  MAX_SCORE,
  TAP_AMOUNT,
  acceptTap,
  materializeDecay,
  percentage,
} from "./heart.js";

const full = () => ({
  score: MAX_SCORE,
  maxScore: MAX_SCORE,
  totalTaps: 0,
  lastUpdatedAt: 1_000,
  lastTapAt: null,
});

describe("linear heart decay", () => {
  it("does not decay before a completed interval", () => {
    expect(materializeDecay(full(), 1_000 + DECAY_INTERVAL_SECONDS - 1).score).toBe(MAX_SCORE);
  });

  it("subtracts exactly 500 per completed 30-minute interval", () => {
    const result = materializeDecay(full(), 1_000 + 10 * DECAY_INTERVAL_SECONDS);
    expect(result.score).toBe(MAX_SCORE - 10 * DECAY_AMOUNT);
    expect(result.lastUpdatedAt).toBe(1_000 + 10 * DECAY_INTERVAL_SECONDS);
  });

  it("never goes below zero", () => {
    expect(materializeDecay(full(), 1_000 + 100 * DECAY_INTERVAL_SECONDS).score).toBe(0);
  });

  it("adds 25 after materializing decay", () => {
    const result = acceptTap({ ...full(), score: 8_000 }, 1_000 + 10 * DECAY_INTERVAL_SECONDS);
    expect(result.score).toBe(3_000 + TAP_AMOUNT);
    expect(result.totalTaps).toBe(1);
  });

  it("reports the intended percentage precision", () => {
    expect(percentage(7_425)).toBe(74.25);
  });
});
