import { addDays, daysBetween } from "./finance/dates";
import { priceKey, type CollectionData, type Grade, type HoldingIdentity, type ISODate, type NormalizedPrice, type PricePoint } from "./types";

/**
 * Graded card prices.
 *
 * The pricing source only covers raw (ungraded) cards, so graded prices come
 * from a separate source. Until a real feed (e.g. PriceCharting) is wired up,
 * `GRADED_SOURCE` is "sample": prices are generated from the raw price with a
 * typical premium for each grade, so every screen can be built and tried.
 * A real feed only has to fill `prices`/`history` under `gradedPriceKey`.
 */
export const GRADED_SOURCE: "sample" | "pricecharting" = "sample";

export const GRADERS = ["PSA", "BGS", "CGC", "SGC", "TAG"] as const;

/** Key for a graded price, alongside the raw `priceKey` entries. */
export function gradedPriceKey(productId: string, printing: string | null, grade: Grade): string {
  return `${priceKey(productId, printing)}|${grade.company.toUpperCase()} ${grade.grade}`;
}

export function gradeLabel(grade: Grade): string {
  return `${grade.company} ${grade.grade}`;
}

/* ------------------------------ Sample source ----------------------------- */

/** Typical multiple of the raw price, by grade (PSA scale). */
const GRADE_MULTIPLE: [number, number][] = [
  [10, 5.2],
  [9.5, 2.6],
  [9, 1.75],
  [8.5, 1.4],
  [8, 1.22],
  [7, 0.98],
  [6, 0.82],
  [5, 0.7],
  [0, 0.55],
];

/** How each company's slabs trade relative to PSA at the same grade. */
const COMPANY_FACTOR: Record<string, number> = { PSA: 1, BGS: 1.05, CGC: 0.72, SGC: 0.7, TAG: 0.66 };

function hash(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return (h >>> 0) / 4294967295;
}

/** Multiple of the raw price for this product and grade (stable per product). */
export function sampleMultiple(productId: string, grade: Grade): number {
  const n = Number.parseFloat(grade.grade);
  const company = grade.company.toUpperCase();
  let base = GRADE_MULTIPLE.find(([g]) => (Number.isFinite(n) ? n : 0) >= g)?.[1] ?? 0.55;
  // A BGS 10 (Black Label) is rarer than a PSA 10.
  if (company === "BGS" && n >= 10) base *= 1.8;
  const factor = COMPANY_FACTOR[company] ?? 0.7;
  // ±18% per product, so premiums differ from card to card.
  const jitter = 0.82 + hash(`${productId}|${company}|${grade.grade}`) * 0.36;
  return Math.max(0.4, base * factor * jitter);
}

function round(n: number) {
  return Math.round(n * 100) / 100;
}

/** Adds sample graded prices and history for every graded identity in the collection. */
export function withSampleGradedPrices(data: CollectionData, today: ISODate): CollectionData {
  if (GRADED_SOURCE !== "sample") return data;
  const graded = new Map<string, HoldingIdentity>();
  for (const t of data.transactions) if (t.grade) graded.set(gradedPriceKey(t.productId, t.printing, t.grade), t);
  if (!graded.size) return data;

  const prices = { ...data.prices };
  const history = { ...data.history };
  for (const [key, id] of graded) {
    if (prices[key]) continue; // a real feed already priced it
    const rawKey = priceKey(id.productId, id.printing);
    const raw = data.prices[rawKey];
    const rawHistory = data.history[rawKey] ?? [];
    const m = sampleMultiple(id.productId, id.grade!);
    // Graded prices move more slowly than raw: a gentle wobble on the raw trend.
    const wobble = (date: ISODate) => 1 + Math.sin(daysBetween("2024-01-01", date) / 9 + hash(key) * 6) * 0.025;
    const points: PricePoint[] = rawHistory.map((p) => ({ date: p.date, price: round(p.price * m * wobble(p.date)) }));
    const market = raw?.market != null ? round(raw.market * m * wobble(today)) : (points.at(-1)?.price ?? null);
    if (market === null) continue;
    if (points.at(-1)?.date !== today) points.push({ date: today, price: market });
    history[key] = points;
    const pctAgo = (days: number) => {
      const from = points.findLast((p) => p.date <= addDays(today, -days));
      return from && from.price > 0 ? ((market - from.price) / from.price) * 100 : null;
    };
    const sample: NormalizedPrice = {
      productId: id.productId,
      printing: id.printing,
      market,
      low: null,
      change24hPct: pctAgo(1),
      change7dPct: pctAgo(7),
      change30dPct: pctAgo(30),
      updatedAt: `${today}T00:00:00.000Z`,
      fetchedAt: null,
      source: "sample",
      status: "live",
    };
    prices[key] = sample;
  }
  return { ...data, prices, history };
}

/** Common grades shown on a product page, with sample prices from the raw price. */
export const LADDER: Grade[] = [
  { company: "PSA", grade: "10" },
  { company: "PSA", grade: "9" },
  { company: "PSA", grade: "8" },
  { company: "BGS", grade: "9.5" },
  { company: "CGC", grade: "10" },
  { company: "SGC", grade: "10" },
];

export interface LadderRow {
  grade: Grade;
  price: number;
  /** Graded price ÷ raw price. */
  multiple: number;
}

export function gradedLadder(productId: string, raw: number | null, grades: Grade[] = LADDER): LadderRow[] {
  if (raw === null || raw <= 0) return [];
  return grades.map((grade) => {
    const multiple = sampleMultiple(productId, grade);
    return { grade, price: round(raw * multiple), multiple };
  });
}

/* --------------------------------- Slabs --------------------------------- */

/** Label colors that echo each company's slab, for the slab frame. */
export const SLAB_STYLE: Record<string, { label: string; text: string; accent: string }> = {
  PSA: { label: "#c8102e", text: "#ffffff", accent: "#ff5a6e" },
  BGS: { label: "#b8bcc4", text: "#111111", accent: "#d9dde4" },
  CGC: { label: "#1d4f91", text: "#ffffff", accent: "#5b8fd6" },
  SGC: { label: "#111111", text: "#ffffff", accent: "#9a9a9a" },
  TAG: { label: "#f2f2f2", text: "#111111", accent: "#cfcfcf" },
};

export function slabStyle(company: string) {
  return SLAB_STYLE[company.toUpperCase()] ?? { label: "#3a3a3c", text: "#ffffff", accent: "#8e8e93" };
}

/** Where to check a certification number. Companies without a direct link get their lookup page. */
export function certLookupUrl(company: string, cert: string): string {
  const c = encodeURIComponent(cert.trim());
  switch (company.toUpperCase()) {
    case "PSA":
      return `https://www.psacard.com/cert/${c}`;
    case "CGC":
      return `https://www.cgccards.com/certlookup/${c}/`;
    case "BGS":
      return "https://www.beckett.com/grading/card-lookup";
    case "SGC":
      return "https://gosgc.com/cert-code-lookup";
    case "TAG":
      return `https://my.taggrading.com/card/${c}`;
    default:
      return `https://www.google.com/search?q=${encodeURIComponent(`${company} cert ${cert}`)}`;
  }
}

/* ------------------------------ Grading math ------------------------------ */

/** A manual valuation older than this is flagged for a refresh. */
export const STALE_VALUE_DAYS = 60;

export function isStaleValue(date: ISODate | null | undefined, today: ISODate): boolean {
  return Boolean(date) && daysBetween(date!, today) > STALE_VALUE_DAYS;
}

export interface GradingCosts {
  /** Grading fee per card. */
  fee: number;
  /** Shipping and insurance per card, both ways. */
  shipping: number;
}

export const DEFAULT_GRADING_COSTS: GradingCosts = { fee: 25, shipping: 12 };

export interface GradingOutlook {
  raw: number;
  cost: number;
  psa10: number;
  psa9: number;
  /** Profit over selling raw if it comes back a PSA 10, after costs. */
  upside10: number;
  /** Profit over selling raw at PSA 9 (negative means a 9 loses money). */
  upside9: number;
}

/** What grading a raw card with PSA would likely be worth. */
export function gradingOutlook(productId: string, raw: number, costs: GradingCosts): GradingOutlook {
  const cost = costs.fee + costs.shipping;
  const psa10 = round(raw * sampleMultiple(productId, { company: "PSA", grade: "10" }));
  const psa9 = round(raw * sampleMultiple(productId, { company: "PSA", grade: "9" }));
  return { raw, cost, psa10, psa9, upside10: psa10 - raw - cost, upside9: psa9 - raw - cost };
}
