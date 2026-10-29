import type { EbaySale, EbaySales, EbayStats } from "./ebay-types";
import { addDays } from "./finance/dates";
import { gradeLabel, LADDER, sampleMultiple, sampleSalesPerYear } from "./graded";
import type { Grade, ISODate } from "./types";

/**
 * Where eBay sold listings come from. "sample" makes up believable sales for
 * every card until TCG API Pro is connected; switch to "tcgapi" then.
 */
export const EBAY_SOURCE: "sample" | "tcgapi" = "sample";

/** Seeded random numbers, so a card's sample sales are the same on every visit. */
function rng(seed: string) {
  let h = 2166136261;
  for (let i = 0; i < seed.length; i++) h = Math.imul(h ^ seed.charCodeAt(i), 16777619);
  let a = h >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const round = (n: number) => Math.round(n * 100) / 100;

function median(xs: number[]) {
  if (!xs.length) return null;
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return round(s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2);
}

function statsOf(sales: EbaySale[]): EbayStats {
  return { median: median(sales.map((s) => s.price)), count: sales.length, lastPrice: sales[0]?.price ?? null, lastSold: sales[0]?.soldDate ?? null };
}

/** Conditions sold, weighted toward Near Mint, with each one's share of the market price. */
const CONDITIONS: [string, number][] = [
  ["Mint", 1.08],
  ["Near Mint", 1],
  ["Near Mint", 1],
  ["Near Mint", 1],
  ["Near Mint", 1],
  ["Near Mint", 1],
  ["Near Mint", 1],
  ["Near Mint", 1],
  ["Lightly Played", 0.82],
  ["Lightly Played", 0.82],
  ["Moderately Played", 0.66],
  ["Heavily Played", 0.5],
  ["Damaged", 0.35],
];

/**
 * Sample eBay sales for a card: ungraded copies around its market price, and
 * graded copies on the same premiums and sales pace the Grading page uses.
 * Links search eBay for the card rather than pointing at made-up listings.
 */
export function sampleEbaySales(productId: string, name: string, printing: string | null, market: number | null, today: ISODate): EbaySales | null {
  if (market === null || market <= 0) return null;
  const rand = rng(`${productId}|${printing ?? ""}|ebay`);
  const search = (extra: string) => `https://www.ebay.com/sch/i.html?_nkw=${encodeURIComponent(`${name} ${extra}`.trim())}&LH_Sold=1&LH_Complete=1`;

  const make = (grade: Grade | null, count: number, center: number): EbaySale[] =>
    Array.from({ length: count }, () => {
      const [condition, factor] = grade ? ([null, 1] as const) : CONDITIONS[Math.floor(rand() * CONDITIONS.length)];
      const price = round(center * factor * (0.86 + rand() * 0.26));
      const bestOffer = rand() < 0.22;
      const label = grade ? gradeLabel(grade) : "";
      return {
        soldDate: addDays(today, -Math.floor(rand() * 30)),
        price,
        bestOffer,
        listPrice: bestOffer ? round(price * (1.08 + rand() * 0.18)) : null,
        grade: grade ? label : null,
        condition: grade ? null : condition,
        title: [grade ? label : null, name, printing && printing !== "Normal" ? printing : null, grade ? null : condition === "Near Mint" ? "NM" : condition].filter(Boolean).join(" "),
        url: search(label),
      };
    });

  // Sales per month from the yearly pace, at least a handful for ungraded.
  const ungraded = make(null, Math.max(6, Math.min(40, Math.round((sampleSalesPerYear(productId, null, market) / 12) * 1.6))), market);
  const graded = LADDER.flatMap((g) => {
    const count = Math.min(25, Math.max(g.company === "PSA" ? 2 : 0, Math.round((sampleSalesPerYear(productId, g, market) / 12) * (1 + rand() * 1.2))));
    return count ? [{ g, sales: make(g, count, market * sampleMultiple(productId, g)) }] : [];
  });

  const byNewest = (a: EbaySale, b: EbaySale) => (a.soldDate < b.soldDate ? 1 : a.soldDate > b.soldDate ? -1 : 0);
  ungraded.sort(byNewest);
  for (const x of graded) x.sales.sort(byNewest);

  return {
    printing,
    ungraded: statsOf(ungraded),
    graded: Object.fromEntries(graded.map((x) => [gradeLabel(x.g), statsOf(x.sales)])),
    sales: [...ungraded, ...graded.flatMap((x) => x.sales)].sort(byNewest),
    asOf: today,
    days: 30,
  };
}
