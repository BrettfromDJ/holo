import type { EbaySale, EbaySales, EbayStats } from "./ebay-types";
import type { Grade } from "./types";

/**
 * CGC 10s come in two kinds: Pristine 10 (the gold label) and Gem Mint 10. eBay files both under
 * "CGC 10", so the two are told apart by the listing's title: one that says "pristine" (any case)
 * is a Pristine 10, the rest are Gem Mint 10s. A slab is marked Pristine per holding
 * (`slab-pristine`). Same as the app's `Pristine` (ios/Holo/Domain/Pristine.swift); the tests
 * check the same cases.
 */

/** What a Pristine 10 usually sells for against a Gem Mint 10 of the same card. */
export const pristinePremium = 1.6;

export const CGC_TEN = "CGC 10";
export const CGC_PRISTINE_10 = "CGC Pristine 10";
export const CGC_GEM_MINT_10 = "CGC Gem Mint 10";

/** Sales this far back (days before the eBay data's `asOf`) count toward the count and median. */
const WINDOW_DAYS = 30;
/** A median needs at least this many sales to stand on its own (same as `MIN_SALES` in worth.ts). */
const MIN_SALES = 2;

export function isPristineTitle(title: string | null | undefined): boolean {
  return /pristine/i.test(title ?? "");
}

/** A CGC 10 (only those can be Pristine). */
export function isCgcTenGrade(company: string | null | undefined, grade: string | null | undefined): boolean {
  return (company ?? "").toUpperCase() === "CGC" && (Number.parseFloat(grade ?? "") || 0) >= 10;
}

/** The label a slab's sales are read under: "CGC Pristine 10" or "CGC Gem Mint 10" for a CGC 10, else "PSA 10" and so on. */
export function slabLabel(grade: Grade, pristine: boolean): string {
  if (!isCgcTenGrade(grade.company, grade.grade)) return `${grade.company} ${grade.grade}`;
  return pristine ? CGC_PRISTINE_10 : CGC_GEM_MINT_10;
}

/** Calendar days from one ISO date (or timestamp) to another; null when unreadable. */
function dayGap(from: string, to: string): number | null {
  const a = Date.parse(`${from.slice(0, 10)}T00:00:00Z`);
  const b = Date.parse(`${to.slice(0, 10)}T00:00:00Z`);
  if (Number.isNaN(a) || Number.isNaN(b)) return null;
  return Math.round((b - a) / 86_400_000);
}

const round = (n: number) => Math.round(n * 100) / 100;

/** CGC 10 sales of one kind, in the order listed (newest first). */
export function cgcTenSales(ebay: EbaySales, pristine: boolean): EbaySale[] {
  return ebay.sales.filter((s) => s.grade === CGC_TEN && isPristineTitle(s.title) === pristine);
}

/**
 * Figures for a set of sales, like eBay's own: the count and median of the last 30 days (before
 * `asOf`), and the latest sale whenever it was. Null when there are no sales at all.
 */
export function statsOfSales(sales: EbaySale[], asOf: string): EbayStats | null {
  if (!sales.length) return null;
  const recent = sales.filter((s) => {
    const gap = dayGap(s.soldDate, asOf);
    return gap === null || gap <= WINDOW_DAYS;
  });
  const prices = recent.map((s) => s.price).sort((a, b) => a - b);
  let median: number | null = null;
  if (prices.length) {
    const m = Math.floor(prices.length / 2);
    median = round(prices.length % 2 ? prices[m] : (prices[m - 1] + prices[m]) / 2);
  }
  let newest = sales[0];
  for (const s of sales) if (s.soldDate > newest.soldDate) newest = s;
  return { median, count: recent.length, lastPrice: newest.price, lastSold: newest.soldDate };
}

/**
 * eBay figures under a label. "CGC Pristine 10" is the CGC 10 sales whose title says pristine;
 * "CGC Gem Mint 10" is the rest (when no listing says pristine, that's every CGC 10 sale, so
 * eBay's own "CGC 10" figures stand). Any other label is eBay's own figures.
 */
export function gradedStats(ebay: EbaySales | null | undefined, label: string): EbayStats | null {
  if (!ebay) return null;
  if (label === CGC_PRISTINE_10) return statsOfSales(cgcTenSales(ebay, true), ebay.asOf);
  if (label === CGC_GEM_MINT_10) {
    if (!ebay.sales.some((s) => s.grade === CGC_TEN && isPristineTitle(s.title))) return ebay.graded[CGC_TEN] ?? null;
    return statsOfSales(cgcTenSales(ebay, false), ebay.asOf);
  }
  return ebay.graded[label] ?? null;
}

/** The listings under a label (the two CGC 10 kinds split by title, as `gradedStats`). */
export function gradedSales(ebay: EbaySales, label: string): EbaySale[] {
  if (label === CGC_PRISTINE_10) return cgcTenSales(ebay, true);
  if (label === CGC_GEM_MINT_10) return cgcTenSales(ebay, false);
  return ebay.sales.filter((s) => s.grade === label);
}

/** A slab's value and whether it rests on enough sales of that exact slab. */
export interface CgcTenValue {
  value: number;
  /** "sales": the median of enough sales; "premium": a Gem Mint 10's value × `pristinePremium`; "other": a price guide or a last sale. */
  basis: "sales" | "premium" | "other";
  /** The figures the value came from, for its date. */
  stats: EbayStats | null;
}

/**
 * What a CGC 10 in your collection is worth.
 * - Gem Mint 10: the median of its sales when there are at least 2, else the price guide
 *   (PriceCharting's one "CGC 10" price, read as a Gem Mint 10), else its median or last sale.
 * - Pristine 10: the median of Pristine sales when there are at least 2, else the Gem Mint 10's
 *   value × `pristinePremium`, else the Pristine median or last sale.
 * Null when nothing prices it. Same as the app's `Pristine.cgcTenValue`.
 */
export function cgcTenValue(gem: EbayStats | null, pristineStats: EbayStats | null, guide: number | null, pristine: boolean): CgcTenValue | null {
  let gemValue: CgcTenValue | null = null;
  if (gem && gem.count >= MIN_SALES && gem.median !== null) gemValue = { value: gem.median, basis: "sales", stats: gem };
  else if (guide !== null) gemValue = { value: guide, basis: "other", stats: null };
  else {
    const v = gem ? (gem.median ?? gem.lastPrice) : null;
    if (v !== null) gemValue = { value: v, basis: "other", stats: gem };
  }
  if (!pristine) return gemValue;
  const p = pristineStats;
  if (p && p.count >= MIN_SALES && p.median !== null) return { value: p.median, basis: "sales", stats: p };
  if (gemValue) return { value: round(gemValue.value * pristinePremium), basis: "premium", stats: gemValue.stats };
  const last = p ? (p.median ?? p.lastPrice) : null;
  return last !== null ? { value: last, basis: "other", stats: p } : null;
}
