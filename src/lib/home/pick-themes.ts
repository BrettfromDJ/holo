import { eraOf, isOversized, type Era } from "@/lib/explore/movers";
import type { Theme } from "@/lib/explore/themes";
import type { ExploreProduct } from "@/lib/explore/types";

/**
 * Home's themed collections, picked the way the app's `ThemesModel` does: Collection of the Day
 * drawn by the date (the launch lineup three times as likely), then a new mix each visit that
 * leans toward fresh and featured ones and away from the ones shown on the last couple of visits.
 */

/** Home's tabs (the app's `HomeFilter`): All, or only one era's cards in every row. */
export type HomeFilter = "all" | Era;
export const HOME_FILTERS: { id: HomeFilter; label: string }[] = [
  { id: "all", label: "All" },
  { id: "modern", label: "Modern" },
  { id: "midEra", label: "Mid era" },
  { id: "vintage", label: "Vintage" },
];

/** Whether a card belongs on a tab, by its set's release date (same cut-offs as `eraOf`). */
export function fitsFilter(filter: HomeFilter, hit: Pick<ExploreProduct, "releaseDate">): boolean {
  return filter === "all" || eraOf(hit.releaseDate) === filter;
}

/** A small seeded random number generator (mulberry32): the same draw for the same seed. */
export function seededRandom(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** One weighted pick. */
export function weightedDraw<T>(list: T[], rand: () => number, weight: (t: T) => number): T | undefined {
  if (!list.length) return undefined;
  const weights = list.map(weight);
  const total = weights.reduce((s, w) => s + w, 0);
  let roll = rand() * total;
  for (let i = 0; i < list.length; i++) {
    if (roll < weights[i]) return list[i];
    roll -= weights[i];
  }
  return list[list.length - 1];
}

/** Days since 1970, plus one (the app's `dayNumber`, so the daily pick changes at midnight UTC). */
export function dayNumber(now = Date.now()): number {
  return Math.floor(now / 86_400_000) + 1;
}

/** Each product once (the market lists can overlap). */
export function uniqueHits<T extends { product: { id: string } }>(hits: T[]): T[] {
  const seen = new Set<string>();
  return hits.filter((h) => !seen.has(h.product.id) && (seen.add(h.product.id), true));
}

/** Themes as Home shows them: no oversized cards, and only those with three cards or more. */
export function cleanThemes(list: Theme[]): Theme[] {
  return list.map((t) => ({ ...t, hits: t.hits.filter((h) => !isOversized(h.product)) })).filter((t) => t.hits.length >= 3);
}

export interface ThemePick {
  daily: Theme | null;
  shown: Theme[];
}

/** Collection of the Day and this visit's rows (up to `count`). */
export function pickThemes(all: Theme[], opts: { day: number; seed: number; recent: Set<string>; count?: number }): ThemePick {
  const count = opts.count ?? 14;
  let pool = all.filter((t) => t.hits.length >= 3);
  const daily = weightedDraw(pool, seededRandom(opts.day), (t) => (t.featured ? 3 : 1)) ?? null;
  pool = pool.filter((t) => t.id !== daily?.id);
  const rand = seededRandom(opts.seed);
  const shown: Theme[] = [];
  while (shown.length < count && pool.length) {
    const chosen = weightedDraw(pool, rand, (t) => {
      let w = 1;
      if (t.fresh) w += 1;
      if (t.featured) w += 0.5;
      if (opts.recent.has(t.id)) w *= 0.15;
      return w;
    });
    if (!chosen) break;
    shown.push(chosen);
    pool = pool.filter((t) => t.id !== chosen.id);
  }
  return { daily, shown };
}

/**
 * For one of Home's tabs: every collection cut down to that era's cards, keeping those with at
 * least `min` left (the day's mix first, then the rest), at most `max`.
 */
export function filteredThemes(pick: ThemePick, all: Theme[], filter: HomeFilter, max = 14, min = 4): Theme[] {
  const ordered = [...(pick.daily ? [pick.daily] : []), ...pick.shown];
  const seen = new Set(ordered.map((t) => t.id));
  ordered.push(...all.filter((t) => !seen.has(t.id)));
  const out: Theme[] = [];
  for (const t of ordered) {
    const hits = t.hits.filter((h) => fitsFilter(filter, h));
    if (hits.length >= min) out.push({ ...t, hits });
    if (out.length >= max) break;
  }
  return out;
}

const RECENT_KEY = "themes-recent";
const LAST_KEY = "themes-last";

/** The collections shown on the last couple of visits (from this browser). */
export function readRecentThemes(): Set<string> {
  try {
    return new Set(JSON.parse(localStorage.getItem(RECENT_KEY) ?? "[]") as string[]);
  } catch {
    return new Set();
  }
}

/** Remember this visit's rows: this visit plus the last one count as "recent" next time. */
export function rememberThemes(ids: string[]) {
  try {
    const last = JSON.parse(localStorage.getItem(LAST_KEY) ?? "[]") as string[];
    localStorage.setItem(LAST_KEY, JSON.stringify(ids));
    localStorage.setItem(RECENT_KEY, JSON.stringify([...new Set([...ids, ...last])]));
  } catch {
    // Storage blocked: the mix just won't avoid last visit's rows.
  }
}
