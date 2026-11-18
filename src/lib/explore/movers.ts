import { categoryOf } from "../catalog";
import type { Product } from "../types";
import type { ExploreProduct } from "./types";

/** A catalog product with its stored 24-hour, 7- and 30-day price change (percent, 12.5 = +12.5%). */
export interface ExploreMover extends ExploreProduct {
  change24hPct?: number | null;
  change7dPct: number | null;
  change30dPct: number | null;
}

/** Explore's market sections: biggest weekly rises and falls among singles, and booster boxes. */
export interface ExploreMarket {
  /** Hot singles: the biggest weekly rises among raw singles. */
  trending: ExploreMover[];
  /** Today's biggest rises among raw singles (the app's Card of the day). */
  today: ExploreMover[];
  /** The biggest weekly rises among singles by era of their set (see `eraOf`). */
  eras: Record<Era, ExploreMover[]>;
  drops: ExploreMover[];
  /** Hot sealed: the biggest weekly rises among sealed products (any kind, never code cards). */
  hotSealed: ExploreMover[];
  boosterBoxes: ExploreMover[];
}

export const EMPTY_MARKET: ExploreMarket = { trending: [], today: [], eras: { modern: [], midEra: [], vintage: [] }, drops: [], hotSealed: [], boosterBoxes: [] };

export type Era = "modern" | "midEra" | "vintage";

/**
 * A set's era by its release date, Dexora's own split (by series):
 * - vintage: everything before Diamond & Pearl (the Wizards of the Coast sets and the EX era, to early 2007);
 * - mid-era: Diamond & Pearl through XY (Diamond & Pearl, Platinum, HeartGold SoulSilver, Black & White, XY; 2007–2016);
 * - modern: Sun & Moon on (2017–now: Sun & Moon, Sword & Shield, Scarlet & Violet, Mega Evolution).
 * Null without a date. Same split as the app's `MarketEras.era`.
 */
export const MID_ERA_FROM = "2007-05-01"; // Diamond & Pearl
export const MODERN_FROM = "2017-02-01"; // Sun & Moon

export function eraOf(releaseDate: string | null | undefined): Era | null {
  if (!releaseDate) return null;
  const day = releaseDate.slice(0, 10);
  if (day < MID_ERA_FROM) return "vintage";
  if (day < MODERN_FROM) return "midEra";
  return "modern";
}

/** Sealed starts higher: a $6 pack moving 30% isn't "hot". */
export const HOT_SEALED_MIN_PRICE = 20;

/** Cheap cards swing by big percentages on one odd sale, so movers start at $20. */
export const MOVER_MIN_PRICE = 20;
export const MOVERS_LIMIT = 12;
export const BOOSTER_BOX_LIMIT = 15;

/** A stored price row, as read from `product_prices` (numeric columns may arrive as strings). */
export interface MoverPriceRow {
  product_id: string;
  printing: string;
  market_price: number | string | null;
  change_24h_pct?: number | string | null;
  change_7d_pct: number | string | null;
  change_30d_pct: number | string | null;
  source_updated_at: string | null;
}

function num(v: number | string | null | undefined): number | null {
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

/** Online game code cards ("Code Card - Surging Sparks Booster Pack"); same rule as the app. */
export function isCodeCard(p: Pick<Product, "name" | "productType" | "rarity">): boolean {
  return /\bcode\s*card\b|\bonline code\b/i.test(`${p.name} ${p.productType ?? ""} ${p.rarity ?? ""}`);
}

/**
 * Oversized (jumbo) cards: never shown anywhere people browse (the owner's rule). Caught by
 * "oversize", "oversized" or "jumbo" in the name, set, rarity, type or number.
 */
export function isOversized(p: Pick<Product, "name" | "productType" | "rarity"> & { setName?: string | null; number?: string | null }): boolean {
  return /over-?\s?sized?|\bjumbo\b/i.test(`${p.name} ${p.setName ?? ""} ${p.productType ?? ""} ${p.rarity ?? ""} ${p.number ?? ""}`);
}

/** A sealed booster box or display (not a bundle, ETB or UPC, which `categoryOf` sorts first). */
export function isBoosterBox(p: Pick<Product, "name" | "productType" | "kind" | "rarity">): boolean {
  return p.kind === "sealed" && !isCodeCard(p) && categoryOf(p) === "Booster Box";
}

function mover(product: Product, row: MoverPriceRow, gameName: string | null): ExploreMover {
  return {
    product,
    printing: row.printing || null,
    market: num(row.market_price),
    priceUpdatedAt: row.source_updated_at,
    gameName,
    change24hPct: num(row.change_24h_pct),
    change7dPct: num(row.change_7d_pct),
    change30dPct: num(row.change_30d_pct),
  };
}

/**
 * The biggest weekly rises ("up") or falls ("down") among singles (or sealed, with `kind`). `rows` should already be
 * ordered by the 7-day change in that direction; each product appears once (its first printing in
 * that order), priced at least `MOVER_MIN_PRICE`, with a real change, never a code card.
 */
export function pickMovers(
  rows: MoverPriceRow[],
  products: Map<string, Product>,
  direction: "up" | "down",
  options: { limit?: number; minPrice?: number; kind?: "single" | "sealed"; gameName?: (p: Product) => string | null; by?: "7d" | "24h" } = {},
): ExploreMover[] {
  const limit = options.limit ?? MOVERS_LIMIT;
  const kind = options.kind ?? "single";
  const minPrice = options.minPrice ?? MOVER_MIN_PRICE;
  const seen = new Set<string>();
  const picked: { row: MoverPriceRow; product: Product; change: number }[] = [];
  for (const row of rows) {
    if (seen.has(row.product_id)) continue;
    const product = products.get(row.product_id);
    if (!product || product.kind !== kind || isCodeCard(product) || isOversized(product)) continue;
    const market = num(row.market_price);
    // By the 7-day change (default), or the 24-hour one (today's movers).
    const change = num(options.by === "24h" ? row.change_24h_pct : row.change_7d_pct);
    if (market === null || market < minPrice || change === null) continue;
    if (direction === "up" ? change <= 0 : change >= 0) continue;
    seen.add(row.product_id);
    picked.push({ row, product, change });
  }
  // Sort here too, so the result doesn't depend on the query's order.
  picked.sort((a, b) => (direction === "up" ? b.change - a.change : a.change - b.change));
  return picked.slice(0, limit).map(({ row, product }) => mover(product, row, options.gameName?.(product) ?? null));
}

/**
 * Booster boxes with a price, most valuable first. Each product's priced printing is used (the
 * first one with a market price).
 */
export function pickBoosterBoxes(
  products: Product[],
  rows: MoverPriceRow[],
  options: { limit?: number; gameName?: (p: Product) => string | null } = {},
): ExploreMover[] {
  const limit = options.limit ?? BOOSTER_BOX_LIMIT;
  const best = new Map<string, MoverPriceRow>();
  for (const row of rows) {
    if (num(row.market_price) === null) continue;
    if (!best.has(row.product_id)) best.set(row.product_id, row);
  }
  const seen = new Set<string>();
  const out: ExploreMover[] = [];
  for (const p of products) {
    if (seen.has(p.id) || !isBoosterBox(p)) continue;
    const row = best.get(p.id);
    if (!row) continue;
    seen.add(p.id);
    out.push(mover(p, row, options.gameName?.(p) ?? null));
  }
  out.sort((a, b) => (b.market ?? 0) - (a.market ?? 0));
  return out.slice(0, limit);
}
