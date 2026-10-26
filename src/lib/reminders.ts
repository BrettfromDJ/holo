"use client";

import { useCallback, useEffect, useState } from "react";

const KEY = "holo:release-reminders:v1";
const EVENT = "holo:reminders";

function read(): string[] {
  try {
    const raw = localStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as string[]) : [];
  } catch {
    return [];
  }
}

/** Sets the user asked to be reminded about, kept in this browser. */
export function useReleaseReminders() {
  const [slugs, setSlugs] = useState<string[]>([]);
  useEffect(() => {
    setSlugs(read());
    const sync = () => setSlugs(read());
    window.addEventListener(EVENT, sync);
    window.addEventListener("storage", sync);
    return () => {
      window.removeEventListener(EVENT, sync);
      window.removeEventListener("storage", sync);
    };
  }, []);
  const toggle = useCallback((slug: string) => {
    const current = read();
    const next = current.includes(slug) ? current.filter((s) => s !== slug) : [...current, slug];
    try {
      localStorage.setItem(KEY, JSON.stringify(next));
    } catch {
      // Storage blocked — the reminder lasts for this page only.
    }
    setSlugs(next);
    window.dispatchEvent(new Event(EVENT));
    return next.includes(slug);
  }, []);
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
