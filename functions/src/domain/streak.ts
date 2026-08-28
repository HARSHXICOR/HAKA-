export interface StreakState {
  current: number;
  longest: number;
  lastCompletedDate: string | null;
}

export interface DailyCompletionState {
  date: string;
  completed: boolean;
  completedAt: number | null;
}

function epochDay(dateKey: string): number {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateKey);
  if (!match) throw new Error("Invalid date key.");
  return Math.floor(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])) / 86_400_000);
}

export function dayDistance(from: string, to: string): number {
  return epochDay(to) - epochDay(from);
}

export function resetStreakForNewDay(
  streak: StreakState,
  previousDay: DailyCompletionState,
  newDate: string,
): void {
  if (!previousDay.completed || dayDistance(previousDay.date, newDate) > 1) {
    streak.current = 0;
  }
}

export function completeDay(
  streak: StreakState,
  day: DailyCompletionState,
  nowSeconds: number,
): void {
  if (day.completed) return;

  const distance = streak.lastCompletedDate ? dayDistance(streak.lastCompletedDate, day.date) : null;
  streak.current = distance === 1 ? streak.current + 1 : 1;
  streak.longest = Math.max(streak.longest, streak.current);
  streak.lastCompletedDate = day.date;
  day.completed = true;
  day.completedAt = nowSeconds;
}
