import { eraOfDate } from "./themes";
import type { ExploreProduct } from "./types";

/**
 * Home's Rising by era, summed up: how each era's whole market moved (the typical change across
 * every priced single in it, not just the risers), how many cards went up and down, and its
 * biggest moves. Uses the 7-day change once enough cards have one, else today's (24 hours).
 */
export type Era = "vintage" | "midEra" | "modern";

export interface EraMove extends ExploreProduct {
  changePct: number;
}

export interface EraSummary {
  era: Era;
  /** Which change the figures use: "7d" (this week) or "24h" (today). */
  window: "7d" | "24h";
  /** The middle change across the era's tracked cards, in percent (2.4 = +2.4%). */
  median: number;
  up: number;
  down: number;
  flat: number;
  tracked: number;
  /** Up to three of the biggest moves either way (from MOVE_MIN_PRICE), biggest first. */
  moves: EraMove[];
}

/** One priced single's changes, with its set's release date. */
export interface EraRow {
  id: string;
  market: number;
  change24h: number | null;
  change7d: number | null;
  releaseDate: string | null;
}

/** Cards needed with a weekly change before an era's summary uses the week. */
export const WEEK_MIN_CARDS = 40;
/** Moves under this count as flat (prices wobble by cents). */
export const FLAT_PCT = 0.5;
/** The biggest moves start at this price, like Home's risers. */
export const MOVE_MIN_PRICE = 20;

function median(values: number[]): number {
  if (!values.length) return 0;
  const s = [...values].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

/** Each era's summary from its cards' rows (moves are ids with their change, picked here). */
export function summarizeEras(rows: EraRow[]): { era: Era; window: "7d" | "24h"; median: number; up: number; down: number; flat: number; tracked: number; moveIds: { id: string; changePct: number }[] }[] {
  const out = [];
  for (const era of ["modern", "midEra", "vintage"] as Era[]) {
    const mine = rows.filter((r) => eraOfDate(r.releaseDate) === era);
    const weekly = mine.filter((r) => r.change7d !== null);
    const window: "7d" | "24h" = weekly.length >= WEEK_MIN_CARDS ? "7d" : "24h";
    const changes = mine.flatMap((r) => {
      const c = window === "7d" ? r.change7d : r.change24h;
      return c === null ? [] : [{ id: r.id, market: r.market, c }];
    });
    const up = changes.filter((x) => x.c >= FLAT_PCT).length;
    const down = changes.filter((x) => x.c <= -FLAT_PCT).length;
    const moveIds = changes
      .filter((x) => x.market >= MOVE_MIN_PRICE && Math.abs(x.c) >= FLAT_PCT)
      .sort((a, b) => Math.abs(b.c) - Math.abs(a.c))
      .slice(0, 3)
      .map((x) => ({ id: x.id, changePct: x.c }));
    out.push({ era, window, median: Math.round(median(changes.map((x) => x.c)) * 10) / 10, up, down, flat: changes.length - up - down, tracked: changes.length, moveIds });
  }
  return out;
}
