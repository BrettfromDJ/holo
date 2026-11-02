import { categoryOf } from "../catalog";
import type { Product } from "../types";
import type { ExploreProduct } from "./types";

/** A catalog product with its stored 7- and 30-day price change (percent, 12.5 = +12.5%). */
export interface ExploreMover extends ExploreProduct {
  change7dPct: number | null;
  change30dPct: number | null;
}

/** Explore's market sections: biggest weekly rises and falls among singles, and booster boxes. */
export interface ExploreMarket {
  trending: ExploreMover[];
  drops: ExploreMover[];
  boosterBoxes: ExploreMover[];
}

export const EMPTY_MARKET: ExploreMarket = { trending: [], drops: [], boosterBoxes: [] };

/** Cheap cards swing by big percentages on pennies, so movers start at $5. */
export const MOVER_MIN_PRICE = 5;
export const MOVERS_LIMIT = 12;
export const BOOSTER_BOX_LIMIT = 15;

/** A stored price row, as read from `product_prices` (numeric columns may arrive as strings). */
export interface MoverPriceRow {
  product_id: string;
  printing: string;
  market_price: number | string | null;
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
    change7dPct: num(row.change_7d_pct),
    change30dPct: num(row.change_30d_pct),
  };
}

/**
 * The biggest weekly rises ("up") or falls ("down") among singles. `rows` should already be
 * ordered by the 7-day change in that direction; each product appears once (its first printing in
 * that order), priced at least `MOVER_MIN_PRICE`, with a real change, never a code card.
 */
export function pickMovers(
  rows: MoverPriceRow[],
  products: Map<string, Product>,
  direction: "up" | "down",
  options: { limit?: number; minPrice?: number; gameName?: (p: Product) => string | null } = {},
): ExploreMover[] {
  const limit = options.limit ?? MOVERS_LIMIT;
  const minPrice = options.minPrice ?? MOVER_MIN_PRICE;
  const seen = new Set<string>();
  const picked: { row: MoverPriceRow; product: Product; change: number }[] = [];
  for (const row of rows) {
    if (seen.has(row.product_id)) continue;
    const product = products.get(row.product_id);
    if (!product || product.kind !== "single" || isCodeCard(product)) continue;
    const market = num(row.market_price);
    const change = num(row.change_7d_pct);
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
