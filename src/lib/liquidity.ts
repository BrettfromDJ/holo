import type { EbaySale, EbaySales } from "./ebay-types";
import type { ISODate } from "./types";

/**
 * "Sells fast": how easy a card (or one grade of it) is to sell, 0 to 100, from this month's
 * eBay sales we already have. Four parts:
 * - volume: how many sold (30 a month is full marks),
 * - tightness: how close the prices were (the middle half's spread against the median),
 * - recency: how recently one sold,
 * - discount: how rarely buyers talked the price down (best offers well under the asking price).
 * Same math as the app's `Liquidity.score` (ios/Holo/Domain/Liquidity.swift).
 */

export type SellSpeedTier = "Sells fast" | "Sells steady" | "Slow to sell";

export interface SellSpeed {
  /** 0–100. */
  score: number;
  tier: SellSpeedTier;
  /** Filled segments of the 3-segment meter: 3 fast, 2 steady, 1 slow. */
  segments: 1 | 2 | 3;
  /** How many sold this month for this grade (or ungraded). */
  sold: number;
}

export const SELL_SPEED_NOTE = "Based on this month's eBay sales: how many sold, how close the prices were, how recently, and how often buyers talked the price down.";

const DAY_MS = 86_400_000;

/** Days from one ISO date (or timestamp) to another, by calendar day; null when unreadable. */
function dayGap(from: string, to: string): number | null {
  const a = Date.parse(`${from.slice(0, 10)}T00:00:00Z`);
  const b = Date.parse(`${to.slice(0, 10)}T00:00:00Z`);
  if (Number.isNaN(a) || Number.isNaN(b)) return null;
  return Math.round((b - a) / DAY_MS);
}

/** Linear-interpolated quantile of sorted numbers (q from 0 to 1). */
export function quantile(sorted: number[], q: number): number {
  const pos = (sorted.length - 1) * q;
  const lo = Math.floor(pos);
  const hi = Math.ceil(pos);
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}

const clamp01 = (n: number) => Math.min(1, Math.max(0, n));

export function sellSpeedTier(score: number): SellSpeedTier {
  return score >= 70 ? "Sells fast" : score >= 40 ? "Sells steady" : "Slow to sell";
}

/**
 * The score for one grade label ("PSA 10"), or ungraded copies when `grade` is null.
 * Null when there isn't enough to go on (fewer than 2 sold and fewer than 2 sales listed).
 */
export function sellSpeed(ebay: EbaySales | null | undefined, grade: string | null, today: ISODate): SellSpeed | null {
  if (!ebay) return null;
  const stats = grade === null ? ebay.ungraded : (ebay.graded[grade] ?? null);
  const sales: EbaySale[] = ebay.sales.filter((s) => (grade === null ? s.grade === null : s.grade === grade));
  const count = stats?.count ?? 0;
  if (count < 2 && sales.length < 2) return null;

  // Volume: 30 sales a month is full marks.
  const v = Math.min(1, Math.log(1 + count) / Math.log(1 + 30));

  // Tightness: the middle half's spread against the median.
  let t = 0.5;
  const prices = sales.map((s) => s.price).sort((a, b) => a - b);
  if (prices.length >= 3) {
    const median = quantile(prices, 0.5);
    if (median > 0) {
      const spread = (quantile(prices, 0.75) - quantile(prices, 0.25)) / median;
      t = clamp01(1 - spread / 0.6);
    }
  }

  // Recency: days since the latest sale, a month or more is none.
  let newest: string | null = stats?.lastSold ?? null;
  if (!newest) for (const s of sales) if (!newest || s.soldDate > newest) newest = s.soldDate;
  const days = newest ? dayGap(newest, today) : null;
  const r = days === null ? 0 : clamp01(1 - Math.max(0, days) / 30);

  // Discount: the share of sales that were best offers well under the asking price.
  const talkedDown = sales.filter((s) => s.bestOffer && s.listPrice !== null && s.price < 0.95 * s.listPrice).length;
  const b = sales.length ? 1 - talkedDown / sales.length : 1;

  const score = Math.round(100 * (0.5 * v + 0.25 * t + 0.15 * r + 0.1 * b));
  const tier = sellSpeedTier(score);
  return { score, tier, segments: tier === "Sells fast" ? 3 : tier === "Sells steady" ? 2 : 1, sold: count };
}
