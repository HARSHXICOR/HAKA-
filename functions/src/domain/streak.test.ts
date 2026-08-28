import { describe, expect, it } from "vitest";
import { completeDay, resetStreakForNewDay } from "./streak.js";

describe("daily streak", () => {
  it("starts on the first completed day", () => {
    const streak = { current: 0, longest: 0, lastCompletedDate: null };
    const day = { date: "2026-08-21", completed: false, completedAt: null };
    completeDay(streak, day, 123);
    expect(streak).toEqual({ current: 1, longest: 1, lastCompletedDate: "2026-08-21" });
    expect(day).toEqual({ date: "2026-08-21", completed: true, completedAt: 123 });
  });

  it("increments once for a consecutive completion", () => {
    const streak = { current: 1, longest: 1, lastCompletedDate: "2026-08-21" };
    const day = { date: "2026-08-22", completed: false, completedAt: null };
    completeDay(streak, day, 456);
    completeDay(streak, day, 457);
    expect(streak).toEqual({ current: 2, longest: 2, lastCompletedDate: "2026-08-22" });
  });

  it("resets after an incomplete or skipped day", () => {
    const streak = { current: 4, longest: 4, lastCompletedDate: "2026-08-20" };
    resetStreakForNewDay(streak, { date: "2026-08-21", completed: false, completedAt: null }, "2026-08-22");
    expect(streak.current).toBe(0);

    const skipped = { current: 4, longest: 4, lastCompletedDate: "2026-08-20" };
    resetStreakForNewDay(skipped, { date: "2026-08-20", completed: true, completedAt: 1 }, "2026-08-22");
    expect(skipped.current).toBe(0);
  });
});
