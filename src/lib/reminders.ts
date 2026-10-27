"use client";

import { useCallback } from "react";
import { useSyncedState } from "./store/synced-state";

const EMPTY: string[] = [];

/** Sets the user asked to be reminded about — synced to the account when signed in. */
export function useReleaseReminders() {
  const [slugs, setSlugs] = useSyncedState<string[]>("release-reminders", EMPTY, { legacyKey: "holo:release-reminders:v1" });
  const toggle = useCallback(
    (slug: string) => {
      const on = !slugs.includes(slug);
      setSlugs((current) => (current.includes(slug) ? current.filter((s) => s !== slug) : [...current, slug]));
      return on;
    },
    [slugs, setSlugs],
  );
  return { slugs, has: (slug: string) => slugs.includes(slug), toggle };
}

/** Whole days from `today` to an ISO date (negative when it's in the past). */
export function daysUntil(date: string, today: string): number {
  return Math.round((Date.parse(`${date}T00:00:00Z`) - Date.parse(`${today}T00:00:00Z`)) / 86_400_000);
}

export function whenLabel(days: number): string {
  if (days === 0) return "Out today";
  if (days === 1) return "Tomorrow";
  if (days > 1) return `In ${days} days`;
  if (days === -1) return "Released yesterday";
  return `Released ${-days} days ago`;
}
