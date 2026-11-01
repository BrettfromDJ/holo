import type { EbaySales } from "./ebay-types";
import { addDays, daysBetween } from "./finance/dates";
import { CGC_GEM_MINT_10, CGC_PRISTINE_10, cgcTenValue, gradedStats, isCgcTenGrade, pristinePremium } from "./pristine";
import { holdingKey, priceKey, type CollectionData, type Grade, type HoldingIdentity, type ISODate, type NormalizedPrice, type PricePoint } from "./types";

/**
 * Graded card prices.
 *
 * The raw pricing source doesn't price slabs. `GRADED_SOURCE` "ebay" prices
 * each slab from the median of recent eBay sales for its exact grade (TCG
 * API Pro), following the raw card's trend for history; a grade with no
 * recent sales stays unpriced so you can enter your own value. Demo
 * products, and everything when set to "sample", get generated prices: the
 * raw price with a typical premium for each grade.
 */
export const GRADED_SOURCE: "sample" | "ebay" = "ebay";

/** Whether a slab of this product is priced from the sample curve. */
export function gradedSampleFor(productId: string) {
  return GRADED_SOURCE === "sample" || productId.startsWith("sample:");
}

export const GRADERS = ["PSA", "BGS", "CGC", "SGC", "TAG"] as const;

/**
 * Key for a graded price, alongside the raw `priceKey` entries. A CGC 10 marked Pristine has its
 * own price ("…|CGC Pristine 10"), apart from the Gem Mint 10s.
 */
export function gradedPriceKey(productId: string, printing: string | null, grade: Grade, pristine = false): string {
  if (pristine && isCgcTenGrade(grade.company, grade.grade)) return `${priceKey(productId, printing)}|${CGC_PRISTINE_10}`;
  return `${priceKey(productId, printing)}|${grade.company.toUpperCase()} ${grade.grade}`;
}

/** Whether this holding is a CGC 10 marked Pristine (`data.pristineSlabs`). */
export function isPristineSlab(data: Pick<CollectionData, "pristineSlabs">, identity: HoldingIdentity): boolean {
  return Boolean(identity.grade && data.pristineSlabs?.length && isCgcTenGrade(identity.grade.company, identity.grade.grade) && data.pristineSlabs.includes(holdingKey(identity)));
}

/** Where a holding's price is kept: its graded key (Pristine apart) for a slab, else the raw key. */
export function holdingPriceKey(data: Pick<CollectionData, "pristineSlabs">, identity: HoldingIdentity): string {
  return identity.grade ? gradedPriceKey(identity.productId, identity.printing, identity.grade, isPristineSlab(data, identity)) : priceKey(identity.productId, identity.printing);
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

/**
 * PriceCharting's prices below 10 mix every company (mostly PSA, which trade a little above the
 * blend). Scales one to a company using the usual gaps between them. Same as the app's
 * `WorthCalc.companyAdjusted`.
 */
export const BLEND_FACTOR = 0.9;
export function companyAdjusted(blended: number, company: string): number {
  return Math.round(((blended * (COMPANY_FACTOR[company.toUpperCase()] ?? 0.7)) / BLEND_FACTOR) * 100) / 100;
}

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
  const graded = new Map<string, HoldingIdentity>();
  const pristineKeys = new Set<string>();
  for (const t of data.transactions) {
    if (!t.grade || !gradedSampleFor(t.productId)) continue;
    const pristine = isPristineSlab(data, t);
    const key = gradedPriceKey(t.productId, t.printing, t.grade, pristine);
    graded.set(key, t);
    if (pristine) pristineKeys.add(key);
  }
  if (!graded.size) return data;

  const prices = { ...data.prices };
  const history = { ...data.history };
  for (const [key, id] of graded) {
    if (prices[key]) continue; // a real feed already priced it
    const rawKey = priceKey(id.productId, id.printing);
    const raw = data.prices[rawKey];
    const rawHistory = data.history[rawKey] ?? [];
    // A Pristine 10 trades at the usual premium over a Gem Mint 10.
    const m = sampleMultiple(id.productId, id.grade!) * (pristineKeys.has(key) ? pristinePremium : 1);
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

/** Label styling per company: wordmark color and label stock. A BGS 10 is a Black Label. */
export interface SlabStyle {
  /** Wordmark and accent stripe. */
  accent: string;
  /** Label background and text. */
  label: string;
  text: string;
}

const LABEL_STOCK = { label: "linear-gradient(180deg, #fbfaf6, #ebe8df)", text: "#1a1a1a" };

export function slabStyle(grade: Grade): SlabStyle {
  const company = grade.company.toUpperCase();
  const n = Number.parseFloat(grade.grade);
  if (company === "BGS" && n >= 10) return { accent: "#d9b45a", label: "linear-gradient(180deg, #1c1c1e, #0c0c0d)", text: "#f2e6c4" };
  const accent = { PSA: "#c8102e", BGS: "#8a8f98", CGC: "#1d4f91", SGC: "#111111", TAG: "#111111" }[company] ?? "#636366";
  return { accent, ...LABEL_STOCK };
}

/** The words printed under the grade, e.g. "GEM MT" for a PSA 10. */
export function gradeDescriptor(grade: Grade): string {
  const n = Number.parseFloat(grade.grade);
  const company = grade.company.toUpperCase();
  if (!Number.isFinite(n)) return "";
  if (company === "PSA") return n >= 10 ? "GEM MT" : n >= 9 ? "MINT" : n >= 8 ? "NM-MT" : n >= 7 ? "NM" : n >= 6 ? "EX-MT" : n >= 5 ? "EX" : n >= 4 ? "VG-EX" : n >= 3 ? "VG" : n >= 2 ? "GOOD" : "POOR";
  // A CGC 10 reads "GEM MINT"; its Pristine 10 is marked per slab (`slab-pristine`) and gets its own label.
  if (n >= 10) return company === "CGC" ? "GEM MINT" : "PRISTINE";
  if (n >= 9.5) return "GEM MINT";
  if (n >= 9) return "MINT";
  if (n >= 8.5) return "NM-MT+";
  if (n >= 8) return "NM-MT";
  return "NEAR MINT";
}

/** Only a CGC 10 can be marked Pristine. */
export function isCgcTen(grade: Grade): boolean {
  return grade.company.toUpperCase() === "CGC" && Number.parseFloat(grade.grade) >= 10;
}

/** The lines printed on a CGC label: the card, the game, "Set - number", then the rarity. */
export function cgcLabelLines(p: { name?: string; setName?: string | null; number?: string | null; rarity?: string | null } | undefined): string[] {
  const set = p?.setName ?? null;
  const num = p?.number ?? null;
  const third = set && num ? `${set} - ${num}` : set ?? (num ? `#${num}` : null);
  return [p?.name ?? "Card", "Pokémon", third, p?.rarity ?? null].filter((l): l is string => Boolean(l));
}

/**
 * A stand-in cert number for a slab with none saved: 10 digits that stay the same for the
 * card (FNV-1a of name|set|number, ending in 001 like CGC's). The app's Slab.fallbackCert matches.
 */
export function fallbackCert(p: { name?: string; setName?: string | null; number?: string | null } | undefined): string {
  const text = [p?.name ?? "Card", p?.setName ?? "", p?.number ?? ""].join("|");
  let h = 2166136261;
  for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 16777619) >>> 0;
  return `${(h % 9000000) + 1000000}001`;
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
  /** PSA 10 sales per year. */
  psa10Sales: number;
  /** Upside at a 10, discounted when PSA 10s rarely sell. Used for ranking. */
  score: number;
  /** Where the PSA prices came from: eBay sales, the usual grade curve on a real card, or demo sample data. */
  source: "sales" | "estimate" | "sample";
}

/** Recent eBay figures for a card's PSA 10 and PSA 9 (30-day medians and sales). */
export interface GradedSales {
  psa10: number | null;
  psa9: number | null;
  /** PSA 10 sales in the last 30 days. */
  psa10Count: number;
}

/**
 * What grading a raw card with PSA would likely be worth. With `sales`, the
 * PSA 10 and 9 prices and sales pace come from eBay; a grade that hasn't sold
 * falls back to the usual grade curve and the outlook is marked an estimate.
 */
export function gradingOutlook(productId: string, raw: number, costs: GradingCosts, sales?: GradedSales | null): GradingOutlook {
  const cost = costs.fee + costs.shipping;
  const curve10 = round(raw * sampleMultiple(productId, { company: "PSA", grade: "10" }));
  const curve9 = round(raw * sampleMultiple(productId, { company: "PSA", grade: "9" }));
  const psa10 = sales?.psa10 ?? curve10;
  const psa9 = sales?.psa9 ?? curve9;
  // Sales pace: from eBay (30 days, scaled to a year) when known, else the sample estimate.
  const psa10Sales = sales ? sales.psa10Count * 12 : sampleSalesPerYear(productId, { company: "PSA", grade: "10" }, raw);
  const upside10 = psa10 - raw - cost;
  const source = !sales ? (gradedSampleFor(productId) ? "sample" : "estimate") : sales.psa10 !== null && sales.psa9 !== null ? "sales" : "estimate";
  return { raw, cost, psa10, psa9, upside10, upside9: psa9 - raw - cost, psa10Sales, score: upside10 * LIQUIDITY_WEIGHT[liquidityOf(psa10Sales)], source };
}

/** A card's PSA 10 and 9 figures from its eBay summary. */
export function gradedSalesFrom(summary: { graded: Record<string, { median: number | null; count: number; lastPrice: number | null }> } | null): GradedSales | null {
  if (!summary) return null;
  const g10 = summary.graded["PSA 10"];
  const g9 = summary.graded["PSA 9"];
  return { psa10: g10?.median ?? g10?.lastPrice ?? null, psa9: g9?.median ?? g9?.lastPrice ?? null, psa10Count: g10?.count ?? 0 };
}

/* ------------------------------ Sales volume ------------------------------ */

/**
 * How many copies sell per year, raw (`grade` null) or at a grade. Sample
 * figures for now (cheaper cards and lower grades sell more often); a real
 * feed such as PriceCharting's sales volume replaces this.
 */
export function sampleSalesPerYear(productId: string, grade: Grade | null, raw: number | null): number {
  const price = raw ?? 50;
  const base = price < 20 ? 420 : price < 100 ? 220 : price < 500 ? 90 : 34;
  let factor = 1;
  if (grade) {
    const n = Number.parseFloat(grade.grade);
    const company = grade.company.toUpperCase();
    factor = company === "PSA" ? (n >= 10 ? 0.14 : n >= 9 ? 0.3 : n >= 8 ? 0.2 : 0.1) : n >= 10 ? 0.05 : 0.08;
  }
  const jitter = 0.4 + hash(`${productId}|${grade ? gradeLabel(grade) : "raw"}|sales`) * 1.2;
  return Math.max(1, Math.round(base * factor * jitter));
}

export type Liquidity = "often" | "regular" | "rare";

/** Weekly or more is "often", monthly or more "regular", anything less "rare". */
export function liquidityOf(perYear: number): Liquidity {
  return perYear >= 52 ? "often" : perYear >= 12 ? "regular" : "rare";
}

/** A plain label for how easy something is to sell: no rates or time periods. */
export function liquidityLabel(perYear: number): string {
  const level = liquidityOf(perYear);
  return level === "often" ? "Easy to sell" : level === "regular" ? "Sells steadily" : "Hard to sell";
}

/** A plain sentence about how easy a slab is to sell. */
export function liquidityNote(perYear: number): string {
  const level = liquidityOf(perYear);
  if (level === "often") return "Easy to sell. Copies sell often, near this price.";
  if (level === "regular") return "Sells steadily. Copies change hands regularly.";
  return "Hard to sell. Copies rarely sell, so a sale may take time or a lower price.";
}

/** How much a grading upside counts when ranking, by how often the PSA 10 sells. */
export const LIQUIDITY_WEIGHT: Record<Liquidity, number> = { often: 1, regular: 0.8, rare: 0.4 };

/* ------------------------------- eBay source ------------------------------ */

/** Slabs to price from eBay: each real product and printing held graded. */
export function ebayGradedTargets(data: CollectionData): { productId: string; printing: string | null }[] {
  const seen = new Map<string, { productId: string; printing: string | null }>();
  for (const t of data.transactions) if (t.grade && !gradedSampleFor(t.productId)) seen.set(priceKey(t.productId, t.printing), { productId: t.productId, printing: t.printing });
  return [...seen.values()];
}

/** PriceCharting's graded values for a product (from /api/graded). */
export interface PriceChartingGraded {
  ungraded: number | null;
  /** "PSA 10", "BGS 10", "CGC 10", "SGC 10" per grader; "9.5", "9", "8", "7" for any grader. */
  grades: Record<string, number>;
  updatedAt: string;
}

/** PriceCharting's value for this exact slab, when it has one. */
export function priceChartingValue(pc: PriceChartingGraded | undefined, grade: Grade): number | null {
  if (!pc) return null;
  const g = Number(grade.grade);
  const key = g === 10 ? `${grade.company.toUpperCase()} 10` : String(g);
  return pc.grades[key] ?? null;
}

/** eBay sales this many or more in 30 days make the median the price; fewer, PriceCharting's. */
export const EBAY_MIN_SALES = 3;

/**
 * Prices slabs for their exact grade: the 30-day eBay median when that grade sold at least
 * EBAY_MIN_SALES times, else PriceCharting's value for the grade, else the last eBay sale.
 * History follows the raw card's trend, scaled to that price. Grades with neither are left
 * unpriced.
 */
export function withEbayGradedPrices(
  data: CollectionData,
  ebay: Record<string, EbaySales | null>,
  today: ISODate,
  pc: Record<string, PriceChartingGraded> = {},
): CollectionData {
  if (GRADED_SOURCE !== "ebay") return data;
  const prices = { ...data.prices };
  const history = { ...data.history };
  let changed = false;
  for (const t of data.transactions) {
    if (!t.grade || gradedSampleFor(t.productId)) continue;
    const pristine = isPristineSlab(data, t);
    const key = gradedPriceKey(t.productId, t.printing, t.grade, pristine);
    if (prices[key]) continue;
    const e = ebay[priceKey(t.productId, t.printing)];
    let stats = e?.graded[gradeLabel(t.grade)];
    let market: number | null;
    let steady: number | null;
    if (isCgcTenGrade(t.grade.company, t.grade.grade)) {
      // A CGC 10: Pristine and Gem Mint priced apart (see `cgcTenValue`); PriceCharting's CGC 10 is a Gem Mint 10.
      const v = cgcTenValue(gradedStats(e, CGC_GEM_MINT_10), gradedStats(e, CGC_PRISTINE_10), priceChartingValue(pc[t.productId], t.grade), pristine);
      market = v?.value ?? null;
      steady = v && v.basis !== "other" && v.stats ? v.value : null;
      stats = v?.stats ?? undefined;
    } else {
      steady = stats && stats.count >= EBAY_MIN_SALES ? stats.median : null;
      market = steady ?? priceChartingValue(pc[t.productId], t.grade) ?? stats?.median ?? stats?.lastPrice ?? null;
    }
    if (market === null) continue;
    const rawKey = priceKey(t.productId, t.printing);
    const raw = data.prices[rawKey]?.market ?? null;
    const ratio = raw ? market / raw : null;
    const points: PricePoint[] = ratio ? (data.history[rawKey] ?? []).filter((p) => p.date < today).map((p) => ({ date: p.date, price: round(p.price * ratio) })) : [];
    points.push({ date: today, price: market });
    history[key] = points;
    prices[key] = {
      productId: t.productId,
      printing: t.printing,
      market,
      low: null,
      change24hPct: null,
      change7dPct: null,
      change30dPct: null,
      updatedAt: steady !== null ? (stats?.lastSold ?? e?.asOf ?? null) : (pc[t.productId]?.updatedAt ?? stats?.lastSold ?? e?.asOf ?? null),
      fetchedAt: null,
      source: "tcgapi",
      status: "live",
    };
    changed = true;
  }
  return changed ? { ...data, prices, history } : data;
}
