import type { EbaySales } from "./ebay-types";
import { sampleMultiple } from "./graded";
import type { Grade } from "./types";

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

export function rawWorth(nm: number, condition: RawCondition, ebay: EbaySales | null): Worth {
  const c = RAW_CONDITIONS.find((x) => x.id === condition)!;
  if (condition === "NM") return { price: nm, source: "market", detail: "TCGplayer market price, Near Mint", sold: null };
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
 * A graded copy's worth. `guide` is the price guide's figure when one is
 * connected; without it, the sample graded curve stands in for the guide.
 */
export function gradedWorth(productId: string, nm: number, grade: Grade, ebay: EbaySales | null, guide?: number | null): Worth {
  const label = `${grade.company} ${grade.grade}`;
  const sold = ebay?.graded[label];
  if (sold && sold.count >= MIN_SALES && sold.median !== null) {
    return { price: sold.median, source: "sales", detail: `Median of ${sold.count} ${label} eBay sales this month`, sold: sold.count };
  }
  const curve = round(nm * sampleMultiple(productId, grade));
  if (guideCovers(grade)) return { price: guide ?? curve, source: "guide", detail: `Price guide for ${label}`, sold: null };
  return { price: curve, source: "estimate", detail: `No recent sales · from the usual grade curve`, sold: null };
}
