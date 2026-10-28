import { addDays } from "../finance/dates";
import {
  DEFAULT_PREFERENCES,
  holdingKey,
  priceKey,
  type CollectionData,
  type Condition,
  type Grade,
  type ISODate,
  type NormalizedPrice,
  type PricePoint,
  type Transaction,
  type WatchlistItem,
} from "../types";
import { SAMPLE_BY_ID, SAMPLE_PRODUCTS, type SampleProduct } from "./catalog";

/**
 * SAMPLE DATA — a realistic but fictional collection used by demo mode.
 * Dates are generated relative to "today" so the demo always looks current.
 * The price series are synthetic and are only ever shown with a "Sample" label.
 */

export const SAMPLE_HISTORY_DAYS = 760;

function mulberry32(seed: number) {
  return () => {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function hash(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return h >>> 0;
}

/** Deterministic Brownian-bridge price series from start price to today's price. */
export function sampleSeries(p: SampleProduct, today: ISODate, days = SAMPLE_HISTORY_DAYS): PricePoint[] {
  const rand = mulberry32(hash(p.id));
  const gauss = () => {
    const u = Math.max(rand(), 1e-9);
    const v = rand();
    return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
  };
  const walk: number[] = [0];
  for (let i = 1; i <= days; i++) walk.push(walk[i - 1] + gauss() * p.vol);
  const a = Math.log(p.sampleStartPrice);
  const b = Math.log(p.samplePrice);
  const out: PricePoint[] = [];
  for (let i = 0; i <= days; i++) {
    const t = i / days;
    const bridge = walk[i] - t * walk[days];
    const price = Math.exp(a + t * (b - a) + bridge);
    out.push({ date: addDays(today, i - days), price: Math.round(price * 100) / 100 });
  }
  return out;
}

function pctChange(points: PricePoint[], back: number): number | null {
  if (points.length <= back) return null;
  const now = points[points.length - 1].price;
  const then = points[points.length - 1 - back].price;
  return then > 0 ? ((now - then) / then) * 100 : null;
}

interface LotSpec {
  product: string;
  daysAgo: number;
  qty: number;
  unit: number;
  shipping?: number;
  fees?: number;
  tax?: number;
  source?: string;
  notes?: string;
  condition?: Condition;
  grade?: Grade;
}

const PURCHASES: LotSpec[] = [
  { product: "es-bb", daysAgo: 742, qty: 1, unit: 289.99, shipping: 0, tax: 23.92, source: "Local game store", notes: "Sealed in original shrink." },
  { product: "es-bb", daysAgo: 610, qty: 1, unit: 398, shipping: 18, source: "eBay" },
  { product: "umbreon-vmax-alt", daysAgo: 700, qty: 1, unit: 540, shipping: 5, fees: 0, source: "TCGplayer", condition: "Near Mint" },
  { product: "rayquaza-vmax-alt", daysAgo: 655, qty: 1, unit: 265, shipping: 4.99, source: "TCGplayer", condition: "Near Mint" },
  { product: "cel-upc", daysAgo: 690, qty: 3, unit: 119.99, tax: 29.7, source: "Pokémon Center" },
  { product: "cz-etb", daysAgo: 600, qty: 2, unit: 49.99, tax: 8.25, source: "Target" },
  { product: "cz-etb", daysAgo: 430, qty: 1, unit: 64.5, shipping: 6, source: "eBay" },
  { product: "151-upc", daysAgo: 520, qty: 2, unit: 119.99, tax: 19.8, source: "Pokémon Center" },
  { product: "151-bundle", daysAgo: 505, qty: 4, unit: 39.99, tax: 13.2, source: "Walmart" },
  { product: "charizard-ex-151", daysAgo: 480, qty: 1, unit: 118, shipping: 4, source: "TCGplayer", condition: "Near Mint" },
  { product: "mew-ex-gold", daysAgo: 470, qty: 2, unit: 43.5, shipping: 4, source: "TCGplayer", condition: "Near Mint" },
  { product: "giratina-v-alt", daysAgo: 400, qty: 1, unit: 228, shipping: 5, source: "Card show", condition: "Near Mint" },
  { product: "charizard-base", daysAgo: 380, qty: 1, unit: 1650, shipping: 25, fees: 0, source: "Heritage Auctions", condition: "Near Mint", grade: { company: "PSA", grade: "8" }, notes: "Cert verified." },
  { product: "rayquaza-vmax-alt", daysAgo: 280, qty: 1, unit: 1380, shipping: 20, source: "PWCC", condition: "Near Mint", grade: { company: "PSA", grade: "10" } },
  { product: "gengar-vmax-alt", daysAgo: 190, qty: 1, unit: 520, shipping: 15, source: "eBay", condition: "Near Mint", grade: { company: "CGC", grade: "9.5" } },
  { product: "tm-bb", daysAgo: 300, qty: 1, unit: 162, shipping: 12, source: "Online retailer" },
  { product: "ss-bb", daysAgo: 250, qty: 2, unit: 149.99, tax: 24.75, source: "Local game store" },
  { product: "pikachu-ex-ss", daysAgo: 210, qty: 1, unit: 289, shipping: 4.5, source: "TCGplayer", condition: "Near Mint" },
  { product: "pe-etb", daysAgo: 160, qty: 2, unit: 139, shipping: 9, source: "eBay", notes: "Paid over MSRP at launch." },
  { product: "pf-tin", daysAgo: 120, qty: 4, unit: 24.99, tax: 8.25, source: "Target" },
  { product: "jt-pack", daysAgo: 45, qty: 12, unit: 4.99, tax: 4.94, source: "Walmart" },
  { product: "pe-etb", daysAgo: 1, qty: 1, unit: 118.75, shipping: 0, source: "Pokémon Center", notes: "Bought at market — shows no artificial gain." },
];

const DISPOSALS: (LotSpec & { type: "sale" | "adjustment" })[] = [
  { type: "sale", product: "cel-upc", daysAgo: 95, qty: 1, unit: 329, fees: 42.8, shipping: 18, source: "eBay", notes: "Partial sale — 1 of 3." },
  { type: "adjustment", product: "151-bundle", daysAgo: 60, qty: -1, unit: 0, notes: "Opened for the binder." },
  { type: "sale", product: "mew-ex-gold", daysAgo: 30, qty: 1, unit: 31, fees: 4.1, shipping: 1, source: "TCGplayer" },
];

const WATCHLIST: { product: string; target: number | null; daysAgo: number }[] = [
  { product: "pe-bundle", target: 50, daysAgo: 20 },
  { product: "lugia-v-alt", target: 240, daysAgo: 40 },
  { product: "dr-etb", target: null, daysAgo: 12 },
  { product: "espeon-vmax-alt", target: 475, daysAgo: 8 },
];

function conditionFor(p: SampleProduct, spec: LotSpec): Condition {
  return spec.condition ?? (p.kind === "sealed" ? "Sealed" : "Near Mint");
}

export function buildDemoData(today: ISODate): CollectionData {
  const products: CollectionData["products"] = {};
  const history: CollectionData["history"] = {};
  const prices: CollectionData["prices"] = {};

  for (const p of SAMPLE_PRODUCTS) {
    const { samplePrice: _a, sampleStartPrice: _b, vol: _c, ...product } = p;
    void _a;
    void _b;
    void _c;
    products[p.id] = product;
    const printing = p.printings?.[0] ?? null;
    const series = sampleSeries(p, today);
    const key = priceKey(p.id, printing);
    // Everything up to yesterday is "stored snapshots"; today is the current quote.
    history[key] = series.slice(0, -1);
    const now = series[series.length - 1].price;
    const quote: NormalizedPrice = {
      productId: p.id,
      printing,
      market: now,
      low: Math.round(now * 0.93 * 100) / 100,
      change24hPct: pctChange(series, 1),
      change7dPct: pctChange(series, 7),
      change30dPct: pctChange(series, 30),
      updatedAt: `${today}T08:00:00.000Z`,
      fetchedAt: `${today}T08:00:00.000Z`,
      source: "sample",
      status: "live",
    };
    prices[key] = quote;
  }

  const transactions: Transaction[] = [];
  let n = 0;
  const createdAt = (daysAgo: number) => `${addDays(today, -daysAgo)}T12:00:${String(n % 60).padStart(2, "0")}.${String(n).padStart(3, "0")}Z`;

  for (const spec of PURCHASES) {
    const p = SAMPLE_BY_ID[`sample:${spec.product}`];
    n++;
    transactions.push({
      id: `sample-tx-${n}`,
      productId: p.id,
      printing: p.printings?.[0] ?? null,
      condition: conditionFor(p, spec),
      grade: spec.grade ?? null,
      type: "purchase",
      date: addDays(today, -spec.daysAgo),
      quantity: spec.qty,
      unitPrice: spec.unit,
      fees: spec.fees ?? 0,
      shipping: spec.shipping ?? 0,
      tax: spec.tax ?? 0,
      source: spec.source ?? null,
      notes: spec.notes ?? null,
      createdAt: createdAt(spec.daysAgo),
    });
  }

  for (const spec of DISPOSALS) {
    const p = SAMPLE_BY_ID[`sample:${spec.product}`];
    n++;
    transactions.push({
      id: `sample-tx-${n}`,
      productId: p.id,
      printing: p.printings?.[0] ?? null,
      condition: conditionFor(p, spec),
      grade: spec.grade ?? null,
      type: spec.type,
      date: addDays(today, -spec.daysAgo),
      quantity: spec.qty,
      unitPrice: spec.unit,
      fees: spec.fees ?? 0,
      shipping: spec.shipping ?? 0,
      tax: spec.tax ?? 0,
      source: spec.source ?? null,
      notes: spec.notes ?? null,
      createdAt: createdAt(spec.daysAgo),
    });
  }

  // An audited correction: the Giratina purchase was first entered at the wrong price.
  const giratina = transactions.find((t) => t.productId === "sample:giratina-v-alt")!;
  n++;
  transactions.push({
    ...giratina,
    id: `sample-tx-${n}`,
    type: "correction",
    correctsId: giratina.id,
    unitPrice: 208,
    notes: "Corrected price — entered seller's asking price by mistake.",
    createdAt: createdAt(398),
  });

  const graded = transactions.find((t) => t.grade)!;
  const manualValues: CollectionData["manualValues"] = {
    [holdingKey(graded)]: { value: 2450, date: graded.date },
  };

  const watchlist: WatchlistItem[] = WATCHLIST.map((w, i) => {
    const p = SAMPLE_BY_ID[`sample:${w.product}`];
    return {
      id: `sample-watch-${i + 1}`,
      productId: p.id,
      printing: p.printings?.[0] ?? null,
      targetPrice: w.target,
      addedAt: `${addDays(today, -w.daysAgo)}T12:00:00.000Z`,
    };
  });

  return { products, transactions, watchlist, prices, history, manualValues, preferences: DEFAULT_PREFERENCES };
}

/** Sample search used by demo mode instead of the live API. */
export function searchSample(q: string, type: "all" | "cards" | "sealed") {
  const terms = q.toLowerCase().split(/\s+/).filter(Boolean);
  return SAMPLE_PRODUCTS.filter((p) => {
    if (type === "cards" && p.kind !== "single") return false;
    if (type === "sealed" && p.kind !== "sealed") return false;
    const hay = `${p.name} ${p.setName} ${p.productType}`.toLowerCase();
    return terms.every((t) => hay.includes(t));
  });
}
