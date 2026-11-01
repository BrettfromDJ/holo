import type { ConditionPrice, EbaySales } from "./ebay-types";
import { companyAdjusted, priceChartingValue, sampleMultiple, type PriceChartingGraded } from "./graded";
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
/** A median needs at least this many sales to stand on its own (the app's `WorthCalc.minSales`). */
export const MIN_SALES = 2;

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

/**
 * Rows of the graded price table. Every row names one company: the 10s by grader, then the
 * grades people trade most below (BGS for 9.5, which PSA doesn't give; PSA below that). The
 * lookup covers the rest. Same as the app's GradedPricesPanel.
 */
export const GRADED_ROWS: { company: WorthGrader; grade: string }[] = [
  { company: "PSA", grade: "10" },
  { company: "BGS", grade: "10" },
  { company: "CGC", grade: "10" },
  { company: "SGC", grade: "10" },
  { company: "BGS", grade: "9.5" },
  { company: "PSA", grade: "9" },
  { company: "PSA", grade: "8" },
  { company: "PSA", grade: "7" },
];

/** The grades people look up for a company, 10 down to 5. */
export function lookupGrades(company: WorthGrader): string[] {
  return gradesFor(company)
    .filter((g) => Number(g) >= 5)
    .reverse();
}

/** Where a slab's price comes from: eBay sales (with how many), PriceCharting as-is, PriceCharting scaled to the company (≈), or the grade curve (≈). */
export type GradedSource = { kind: "ebay"; count: number } | { kind: "guide" } | { kind: "adjusted" } | { kind: "curve" };

export interface GradedPrice {
  value: number;
  source: GradedSource;
}

/** Whether a price is an estimate (shown with ≈). */
export function isEstimate(source: GradedSource): boolean {
  return source.kind === "adjusted" || source.kind === "curve";
}

/** The small word beside a price in the table. */
export function gradedSourceLabel(source: GradedSource): string {
  return source.kind === "ebay" ? "eBay" : source.kind === "guide" ? "PriceCharting" : "estimate";
}

/**
 * One slab's price: recent eBay sales of that exact slab when there are enough, else
 * PriceCharting (its 10s are per company; below 10 its one price for every company is scaled to
 * this company, ≈), else the last eBay sale, else the usual grade curve (≈). Same as the app's
 * `GradedPricesPanel.price`.
 */
export function gradedPrice(productId: string, grade: Grade, pc: PriceChartingGraded | null | undefined, ebay: EbaySales | null, nm: number | null): GradedPrice | null {
  const label = `${grade.company} ${grade.grade}`;
  const sold = ebay?.graded[label];
  if (sold && sold.count >= MIN_SALES && sold.median !== null) return { value: sold.median, source: { kind: "ebay", count: sold.count } };
  const v = priceChartingValue(pc ?? undefined, grade);
  if (v !== null) return Number(grade.grade) < 10 ? { value: companyAdjusted(v, grade.company), source: { kind: "adjusted" } } : { value: v, source: { kind: "guide" } };
  const last = sold ? (sold.lastPrice ?? sold.median) : null;
  if (sold && last !== null) return { value: last, source: { kind: "ebay", count: sold.count } };
  if (nm !== null && nm > 0) return { value: round(nm * sampleMultiple(productId, grade)), source: { kind: "curve" } };
  return null;
}

export interface GradedLookup {
  price: number | null;
  source: GradedSource | null;
  /** Where the number came from, in plain words. */
  detail: string;
}

/** Any company and grade, with where the number came from in plain words (same as the app's lookup). */
export function gradedLookup(productId: string, nm: number | null, grade: Grade, ebay: EbaySales | null, pc: PriceChartingGraded | null | undefined): GradedLookup {
  const label = `${grade.company} ${grade.grade}`;
  const p = gradedPrice(productId, grade, pc, ebay, nm);
  if (!p) return { price: null, source: null, detail: "No sales or price guide for this grade yet" };
  const s = p.source;
  const detail =
    s.kind === "ebay"
      ? s.count >= MIN_SALES
        ? `Median of ${s.count} ${label} eBay sales this month`
        : `Last ${label} eBay sale`
      : s.kind === "guide"
        ? `PriceCharting · ${label}`
        : s.kind === "adjusted"
          ? `Estimate · PriceCharting's grade ${grade.grade} price for any company, adjusted for ${grade.company}`
          : "Estimate from the usual grade curve";
  return { price: p.value, source: s, detail };
}

/**
 * A PSA grade for a raw card you own: PriceCharting's value (its 9 is for any company, so it's
 * scaled to PSA and marked an estimate), else the curve (an estimate). Same as the app's If graded.
 */
export function psaIfGraded(productId: string, nm: number, grade: "10" | "9", pc: PriceChartingGraded | null | undefined): { price: number; estimate: boolean } {
  const v = priceChartingValue(pc ?? undefined, { company: "PSA", grade });
  if (v !== null) return grade === "10" ? { price: v, estimate: false } : { price: companyAdjusted(v, "PSA"), estimate: true };
  return { price: round(nm * sampleMultiple(productId, { company: "PSA", grade })), estimate: true };
}
