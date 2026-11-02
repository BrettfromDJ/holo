import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import { EMPTY_MARKET, isBoosterBox, pickBoosterBoxes, pickMovers, type ExploreMarket, type MoverPriceRow } from "../explore/movers";
import type { ExploreProduct, ExploreSet } from "../explore/types";
import type { Product } from "../types";
import type { CatalogSetRow, Database, ProductRow } from "../supabase/database.types";
import { productFromRow } from "../supabase/mappers";
import { selectAll } from "./paging";

/** Browsing is read from Supabase only — never from the TCG API. Cached at the CDN for ten minutes. */
export const EXPLORE_CACHE = "public, s-maxage=600, stale-while-revalidate=3600";

export function setFromRow(r: CatalogSetRow): ExploreSet {
  return {
    slug: r.slug,
    gameSlug: r.game_slug,
    gameName: r.game_name,
    name: r.name,
    releaseDate: r.release_date,
    imageUrl: r.image_url,
    iconUrl: r.icon_url,
    productCount: r.product_count,
    loaded: Boolean(r.products_synced_at),
    syncedAt: r.products_synced_at,
  };
}

/** Attach each product's stored price (default printing first). */
export async function withPrices(admin: SupabaseClient<Database>, rows: ProductRow[]): Promise<ExploreProduct[]> {
  const ids = rows.map((r) => r.id);
  const prices = new Map<string, { printing: string; market_price: number | null; source_updated_at: string | null }>();
  // Several printings per product, so keep each request well under the 1,000-row cap.
  for (let i = 0; i < ids.length; i += 150) {
    const { data } = await admin.from("product_prices").select("product_id, printing, market_price, source_updated_at").in("product_id", ids.slice(i, i + 150));
    for (const p of data ?? []) {
      const prev = prices.get(p.product_id);
      // Prefer the row with a price; otherwise keep the first.
      if (!prev || (prev.market_price === null && p.market_price !== null)) prices.set(p.product_id, p);
    }
  }
  // Brand names and release dates, from each product's set.
  const setIds = [...new Set(rows.map((r) => r.set_id).filter((x): x is string => Boolean(x)))];
  const brands = new Map<string, string>();
  const released = new Map<string, string>();
  for (let i = 0; i < setIds.length; i += 300) {
    const { data } = await admin.from("catalog_sets").select("slug, game_name, release_date").in("slug", setIds.slice(i, i + 300));
    for (const s of data ?? []) {
      brands.set(s.slug, s.game_name);
      if (s.release_date) released.set(s.slug, s.release_date);
    }
  }
  return rows.map((r) => {
    const p = prices.get(r.id);
    return {
      product: productFromRow(r),
      printing: p?.printing || null,
      market: p?.market_price === null || p?.market_price === undefined ? null : Number(p.market_price),
      priceUpdatedAt: p?.source_updated_at ?? null,
      gameName: r.set_id ? (brands.get(r.set_id) ?? null) : null,
      releaseDate: r.set_id ? (released.get(r.set_id) ?? null) : null,
    };
  });
}

/** Brand names, from each product's set. */
async function brandNames(admin: SupabaseClient<Database>, setIdList: (string | null)[]): Promise<Map<string, string>> {
  const setIds = [...new Set(setIdList.filter((x): x is string => Boolean(x)))];
  const brands = new Map<string, string>();
  for (let i = 0; i < setIds.length; i += 300) {
    const { data } = await admin.from("catalog_sets").select("slug, game_name").in("slug", setIds.slice(i, i + 300));
    for (const s of data ?? []) brands.set(s.slug, s.game_name);
  }
  return brands;
}

const MOVER_COLUMNS = "product_id, printing, market_price, change_7d_pct, change_30d_pct, source_updated_at";
/** Price rows read per direction: more than shown, since sealed rows and extra printings drop out. */
const MOVER_SCAN = 150;

async function productsById(admin: SupabaseClient<Database>, ids: string[]): Promise<Map<string, Product>> {
  const out = new Map<string, Product>();
  const unique = [...new Set(ids)];
  for (let i = 0; i < unique.length; i += 150) {
    const { data, error } = await admin.from("products").select("*").in("id", unique.slice(i, i + 150));
    if (error) throw new Error(error.message);
    for (const r of data ?? []) out.set(r.id, productFromRow(r));
  }
  return out;
}

/**
 * Explore's market sections, from stored prices only (never the TCG API): singles with the
 * biggest 7-day rise and fall, and booster boxes by price. The release price isn't stored, so
 * boxes carry 7- and 30-day changes. Any failure leaves the sections empty.
 */
export async function exploreMarket(admin: SupabaseClient<Database>): Promise<ExploreMarket> {
  try {
    const moversQuery = (ascending: boolean) => {
      const q = admin.from("product_prices").select(MOVER_COLUMNS).gte("market_price", 5).not("change_7d_pct", "is", null);
      return (ascending ? q.lt("change_7d_pct", 0) : q.gt("change_7d_pct", 0)).order("change_7d_pct", { ascending }).limit(MOVER_SCAN);
    };
    const [upRes, downRes, boxRows] = await Promise.all([
      moversQuery(false),
      moversQuery(true),
      // Booster boxes and displays; `isBoosterBox` drops bundles and the like that also match.
      selectAll<ProductRow>(
        (from, to) =>
          admin
            .from("products")
            .select("*")
            .eq("source", "tcgapi")
            .eq("kind", "sealed")
            .or("name.ilike.*booster box*,name.ilike.*booster display*,name.ilike.*display box*,product_type.ilike.*booster box*")
            .order("id")
            .range(from, to),
        5000,
      ),
    ]);
    if (upRes.error) throw new Error(upRes.error.message);
    if (downRes.error) throw new Error(downRes.error.message);
    const up = (upRes.data ?? []) as MoverPriceRow[];
    const down = (downRes.data ?? []) as MoverPriceRow[];

    const boxes = boxRows.map(productFromRow).filter(isBoosterBox);
    const boxPrices: MoverPriceRow[] = [];
    for (let i = 0; i < boxes.length; i += 150) {
      const { data } = await admin.from("product_prices").select(MOVER_COLUMNS).in("product_id", boxes.slice(i, i + 150).map((b) => b.id));
      boxPrices.push(...((data ?? []) as MoverPriceRow[]));
    }

    const products = await productsById(admin, [...up, ...down].map((r) => r.product_id));
    const trendingRaw = pickMovers(up, products, "up");
    const dropsRaw = pickMovers(down, products, "down");
    const boxesRaw = pickBoosterBoxes(boxes, boxPrices);
    const brands = await brandNames(admin, [...trendingRaw, ...dropsRaw, ...boxesRaw].map((m) => m.product.setId));
    const named = <T extends { product: Product; gameName?: string | null }>(m: T): T => ({ ...m, gameName: m.product.setId ? (brands.get(m.product.setId) ?? null) : null });
    return { trending: trendingRaw.map(named), drops: dropsRaw.map(named), boosterBoxes: boxesRaw.map(named) };
  } catch (e) {
    console.error("explore market", e);
    return EMPTY_MARKET;
  }
}
