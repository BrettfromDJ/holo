import type { ConditionPrice, EbaySales } from "./ebay-types";
import { priceChartingValue, sampleMultiple, type PriceChartingGraded } from "./graded";
import type { Condition, Grade } from "./types";

/**
 * "What's it worth?" for one card in one condition or grade, with where the
 * number came from. In order of trust: recent eBay sales, a price guide
 * (PriceCharting covers 7, 8, 9, 9.5 and each company's 10), then an
 * estimate (a share of Near Mint, or the usual grade curve), always labeled.
 */

export type RawCondition = "NM" | "LP" | "MP" | "HP" | "DMG";

export const RAW_CONDITIONS: { id: RawCondition; label: string; share: number }[] = [
  { id: "NM", label: "Near Mint", share: 1 },
  { id: "LP", label: "Lightly Played", share: 0.85 },
  { id: "MP", label: "Moderately Played", share: 0.7 },
  { id: "HP", label: "Heavily Played", share: 0.5 },
  { id: "DMG", label: "Damaged", share: 0.35 },
];

/** Share of Near Mint a raw copy in this condition is estimated at (sealed and Near Mint are 1). */
export function conditionShare(condition: Condition): number {
  return RAW_CONDITIONS.find((c) => c.label === condition)?.share ?? 1;
}

export const WORTH_GRADERS = ["PSA", "BGS", "CGC", "SGC", "TAG"] as const;
export type WorthGrader = (typeof WORTH_GRADERS)[number];

/** Grades each company gives: whole grades, plus halves where they use them. */
export function gradesFor(company: WorthGrader): string[] {
  const whole = Array.from({ length: 10 }, (_, i) => String(i + 1));
  if (company === "BGS" || company === "CGC") return [...whole.slice(0, 7), "7.5", "8", "8.5", "9", "9.5", "10"];
  return whole;
}

/** Grades a price guide like PriceCharting lists for cards. */
function guideCovers(grade: Grade) {
  const g = grade.grade;
  if (g === "10") return ["PSA", "BGS", "CGC", "SGC"].includes(grade.company);
  return ["7", "8", "9", "9.5"].includes(g);
}

export type WorthSource = "market" | "sales" | "guide" | "estimate";

export interface Worth {
  price: number;
  source: WorthSource;
  /** Plain-language note on where the number came from. */
  detail: string;
  /** Sales the number rests on, when it comes from sales. */
  sold: number | null;
}

const round = (n: number) => Math.round(n * 100) / 100;
/** A median needs at least this many sales to stand on its own. */
const MIN_SALES = 2;

/**
 * A raw copy's worth. Near Mint is the market price; other conditions use
 * TCGplayer's price for that condition, then eBay sales in it, then a share
 * of Near Mint.
 */
export function rawWorth(nm: number, condition: RawCondition, ebay: EbaySales | null, conditions?: ConditionPrice[] | null, printing?: string | null): Worth {
  const c = RAW_CONDITIONS.find((x) => x.id === condition)!;
  if (condition === "NM") return { price: nm, source: "market", detail: "TCGplayer market price, Near Mint", sold: null };
  const rows = (conditions ?? []).filter((r) => r.condition === c.label && r.price !== null);
  const listed = rows.find((r) => r.printing === (printing ?? null)) ?? rows[0];
  if (listed?.price != null) {
    return { price: round(listed.price), source: "market", detail: listed.basis === "median" ? `TCGplayer ${c.label} listings · median of ${listed.samples}` : `Lowest TCGplayer ${c.label} listing`, sold: null };
  }
  const sales = (ebay?.sales ?? []).filter((s) => s.grade === null && s.condition === c.label).map((s) => s.price);
  if (sales.length >= MIN_SALES + 1) {
    const sorted = [...sales].sort((a, b) => a - b);
    const m = Math.floor(sorted.length / 2);
    const median = sorted.length % 2 ? sorted[m] : (sorted[m - 1] + sorted[m]) / 2;
    return { price: round(median), source: "sales", detail: `Median of ${sales.length} ${c.label} eBay sales this month`, sold: sales.length };
  }
  return { price: round(nm * c.share), source: "estimate", detail: `Estimated at ${Math.round(c.share * 100)}% of Near Mint`, sold: null };
}

/**
 * A graded copy's worth. `guide` is a price guide's figure (PriceCharting)
 * when one is connected. `curveIsGuide` lets the sample grade curve stand in
 * for the guide on demo products; on real ones, without a guide or sales,
 * the curve is an estimate and says so.
 */
export function gradedWorth(productId: string, nm: number, grade: Grade, ebay: EbaySales | null, guide?: number | null, curveIsGuide = false): Worth {
  const label = `${grade.company} ${grade.grade}`;
  const sold = ebay?.graded[label];
  if (sold && sold.count >= MIN_SALES && sold.median !== null) {
    return { price: sold.median, source: "sales", detail: `Median of ${sold.count} ${label} eBay sales this month`, sold: sold.count };
  }
  const curve = round(nm * sampleMultiple(productId, grade));
  if (guideCovers(grade) && (guide != null || curveIsGuide)) return { price: guide ?? curve, source: "guide", detail: `Price guide for ${label}`, sold: null };
  return { price: curve, source: "estimate", detail: `No recent sales · from the usual grade curve`, sold: null };
}

/**
 * Each played condition's price as a share of Near Mint, from TCGplayer's per-condition prices
 * for one card. Kept between 5% and 100% so one odd listing can't swing a value wildly.
 */
export function measuredShares(all: { condition: string; price: number | null; printing?: string | null }[], printing?: string | null): Record<string, number> {
  // One printing's rows: the one asked for, else the first one that has a Near Mint price.
  const pick = printing !== undefined && all.some((r) => r.printing === printing) ? printing : all.find((r) => r.condition === "Near Mint" && r.price)?.printing;
  const rows = pick !== undefined ? all.filter((r) => r.printing === pick) : all;
  const nm = rows.find((r) => r.condition === "Near Mint")?.price;
  if (!nm || nm <= 0) return {};
  const out: Record<string, number> = {};
  for (const r of rows) {
    if (r.condition === "Near Mint" || !r.price || r.price <= 0) continue;
    out[r.condition] = Math.min(1, Math.max(0.05, r.price / nm));
  }
  return out;
}

/* ----------------------------- Graded prices ------------------------------ */

/** Rows of the graded price table: the 10s by grader, then any grader below (PriceCharting's keys). */
export const GRADED_ROWS: { key: string; company: string | null; grade: string }[] = [
  { key: "PSA 10", company: "PSA", grade: "10" },
  { key: "BGS 10", company: "BGS", grade: "10" },
  { key: "CGC 10", company: "CGC", grade: "10" },
  { key: "SGC 10", company: "SGC", grade: "10" },
  { key: "9.5", company: null, grade: "9.5" },
  { key: "9", company: null, grade: "9" },
  { key: "8", company: null, grade: "8" },
  { key: "7", company: null, grade: "7" },
];

/** The grades people look up for a company, 10 down to 5. */
export function lookupGrades(company: WorthGrader): string[] {
  return gradesFor(company)
    .filter((g) => Number(g) >= 5)
    .reverse();
}

/** The graded table from the usual grade curve, for a card PriceCharting doesn't cover. */
export function estimatedGradedTable(productId: string, nm: number | null): PriceChartingGraded | null {
  if (nm === null || !(nm > 0)) return null;
  const grades: Record<string, number> = {};
  for (const r of GRADED_ROWS) grades[r.key] = round(nm * sampleMultiple(productId, { company: r.company ?? "PSA", grade: r.grade }));
  return { ungraded: nm, grades, updatedAt: "" };
}

export interface GradedLookup {
  price: number | null;
  source: "sales" | "guide" | "estimate" | null;
  /** Where the number came from, in plain words. */
  detail: string;
}

/**
 * Any company and grade: the eBay median for that exact slab when it sold enough, else
 * PriceCharting's value (10s per company, lower grades for any company), else the last eBay
 * sale, else the usual grade curve from raw Near Mint.
 */
export function gradedLookup(productId: string, nm: number | null, grade: Grade, ebay: EbaySales | null, pc: PriceChartingGraded | null | undefined): GradedLookup {
  const label = `${grade.company} ${grade.grade}`;
  const sold = ebay?.graded[label];
  if (sold && sold.count >= MIN_SALES && sold.median !== null) return { price: sold.median, source: "sales", detail: `Median of ${sold.count} ${label} eBay sales this month` };
  const guide = priceChartingValue(pc ?? undefined, grade);
  if (guide !== null) return { price: guide, source: "guide", detail: Number(grade.grade) < 10 ? `PriceCharting · grade ${grade.grade}, any grading company` : `PriceCharting · ${label}` };
  const last = sold ? (sold.lastPrice ?? sold.median) : null;
  if (last !== null) return { price: last, source: "sales", detail: `Last ${label} eBay sale` };
  if (nm !== null && nm > 0) return { price: round(nm * sampleMultiple(productId, grade)), source: "estimate", detail: "Estimate from the usual grade curve" };
  return { price: null, source: null, detail: "No sales or price guide for this grade yet" };
}

/** A PSA grade for a raw card you own: PriceCharting's value, else the curve (an estimate). */
export function psaIfGraded(productId: string, nm: number, grade: "10" | "9", pc: PriceChartingGraded | null | undefined): { price: number; estimate: boolean } {
  const v = priceChartingValue(pc ?? undefined, { company: "PSA", grade });
  if (v !== null) return { price: v, estimate: false };
  return { price: round(nm * sampleMultiple(productId, { company: "PSA", grade })), estimate: true };
}
