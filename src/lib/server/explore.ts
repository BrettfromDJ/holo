import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { ExploreProduct, ExploreSet } from "../explore/types";
import type { CatalogSetRow, Database, ProductRow } from "../supabase/database.types";
import { productFromRow } from "../supabase/mappers";

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
  // Brand names, from each product's set.
  const setIds = [...new Set(rows.map((r) => r.set_id).filter((x): x is string => Boolean(x)))];
  const brands = new Map<string, string>();
  for (let i = 0; i < setIds.length; i += 300) {
    const { data } = await admin.from("catalog_sets").select("slug, game_name").in("slug", setIds.slice(i, i + 300));
    for (const s of data ?? []) brands.set(s.slug, s.game_name);
  }
  return rows.map((r) => {
    const p = prices.get(r.id);
    return {
      product: productFromRow(r),
      printing: p?.printing || null,
      market: p?.market_price === null || p?.market_price === undefined ? null : Number(p.market_price),
      priceUpdatedAt: p?.source_updated_at ?? null,
      gameName: r.set_id ? (brands.get(r.set_id) ?? null) : null,
    };
  });
}
