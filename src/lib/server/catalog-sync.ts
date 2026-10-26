import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import { catalogGameList, gameSetsPage, setProductsPage } from "../pricing/tcgapi";
import { PricingUnavailableError } from "../pricing/types";
import type { Database } from "../supabase/database.types";
import { priceToRow, productToRow } from "../supabase/mappers";
import type { NormalizedPrice } from "../types";

const DAY = 24 * 60 * 60 * 1000;

export interface CatalogSyncOptions {
  /** Most TCG API requests this run may make. A real 429 also stops it. */
  maxCalls: number;
}

export interface CatalogSyncResult {
  calls: number;
  setsListed: number;
  setsSynced: string[];
  productsSeen: number;
  pricesStored: number;
  stoppedBecause: "done" | "budget" | "rate_limited" | "error";
  error?: string;
}

/**
 * Fills the Explore catalog a little at a time so browsing never touches the
 * TCG API:
 *
 * 1. Once a week, refresh the list of sets for every catalog (a few calls).
 * 2. Load products for sets that have never been loaded (newest first), then
 *    re-load the stalest ones to refresh their prices — until the budget for
 *    this run is used.
 *
 * Products are inserted but never overwritten, so a type the user corrected
 * stays corrected. Prices are only written where the daily price sync hasn't
 * already stored a fresher one.
 */
export async function syncCatalog(admin: SupabaseClient<Database>, opts: CatalogSyncOptions): Promise<CatalogSyncResult> {
  const result: CatalogSyncResult = { calls: 0, setsListed: 0, setsSynced: [], productsSeen: 0, pricesStored: 0, stoppedBecause: "done" };
  // The "remaining" figure TCG API reports doesn't always match its dashboard,
  // so it never blocks the sync; only the per-run cap and a real 429 do.
  const canCall = () => result.calls < opts.maxCalls;

  try {
    // --- 1. Set lists (weekly) ---------------------------------------------
    const { data: newest } = await admin.from("catalog_sets").select("listed_at").order("listed_at", { ascending: false }).limit(1);
    const listStale = !newest?.length || Date.now() - Date.parse(newest[0].listed_at) > 7 * DAY;
    if (listStale) {
      for (const game of await catalogGameList()) {
        for (let page = 1; page <= 5; page++) {
          if (!canCall()) return { ...result, stoppedBecause: "budget" };
          result.calls++;
          const { sets, hasMore } = await gameSetsPage(game.slug, page);
          if (sets.length) {
            const rows = sets.map((s) => ({
              slug: s.slug,
              tcgapi_id: s.id,
              game_slug: game.slug,
              game_name: s.game_name ?? game.name,
              name: s.name,
              abbreviation: s.abbreviation,
              release_date: s.release_date ? s.release_date.slice(0, 10) : null,
              card_count: s.card_count,
              image_url: s.image_url,
              icon_url: s.set_icon_url,
              listed_at: new Date().toISOString(),
            }));
            const { error } = await admin.from("catalog_sets").upsert(rows);
            if (error) throw new Error(error.message);
            result.setsListed += rows.length;
          }
          if (!hasMore) break;
        }
      }
    }

    // --- 2. Products, newest unloaded sets first, then the stalest ----------
    const { data: queue, error: qErr } = await admin
      .from("catalog_sets")
      .select("slug, tcgapi_id, name, products_synced_at")
      .order("products_synced_at", { ascending: true, nullsFirst: true })
      .order("release_date", { ascending: false, nullsFirst: false })
      .limit(500);
    if (qErr) throw new Error(qErr.message);

    for (const set of queue ?? []) {
      // Recently loaded sets don't need another pass yet.
      if (set.products_synced_at && Date.now() - Date.parse(set.products_synced_at) < 3 * DAY) break;
      let count = 0;
      let finished = false;
      for (let page = 1; page <= 10; page++) {
        if (!canCall()) return { ...result, stoppedBecause: "budget" };
        result.calls++;
        const { products, prices, hasMore } = await setProductsPage({ id: set.tcgapi_id, slug: set.slug, name: set.name }, page);
        count += products.length;
        result.productsSeen += products.length;
        if (products.length) {
          const { error } = await admin.from("products").upsert(products.map(productToRow), { onConflict: "id", ignoreDuplicates: true });
          if (error) throw new Error(error.message);
          result.pricesStored += await storePrices(admin, prices);
        }
        if (!hasMore) {
          finished = true;
          break;
        }
      }
      if (finished) {
        const { error } = await admin.from("catalog_sets").update({ products_synced_at: new Date().toISOString(), product_count: count }).eq("slug", set.slug);
        if (error) throw new Error(error.message);
        result.setsSynced.push(set.slug);
      }
    }
    return result;
  } catch (err) {
    if (err instanceof PricingUnavailableError && err.code === "rate_limited") return { ...result, stoppedBecause: "rate_limited" };
    return { ...result, stoppedBecause: "error", error: err instanceof Error ? err.message : String(err) };
  }
}

/** Store prices and today's snapshot, skipping products priced in the last day and a half. */
async function storePrices(admin: SupabaseClient<Database>, prices: NormalizedPrice[]): Promise<number> {
  const rows = prices.map(priceToRow);
  const ids = [...new Set(rows.map((r) => r.product_id))];
  const { data: existing } = await admin.from("product_prices").select("product_id, fetched_at").in("product_id", ids);
  const fresh = new Set((existing ?? []).filter((r) => Date.now() - Date.parse(r.fetched_at) < 1.5 * DAY).map((r) => r.product_id));
  const toWrite = rows.filter((r) => !fresh.has(r.product_id));
  if (!toWrite.length) return 0;
  const { error } = await admin.from("product_prices").upsert(toWrite);
  if (error) throw new Error(error.message);
  const today = new Date().toISOString().slice(0, 10);
  const snaps = toWrite
    .filter((r) => r.market_price !== null)
    .map((r) => ({ product_id: r.product_id, printing: r.printing, snapshot_date: today, market_price: r.market_price as number, source: r.source }));
  if (snaps.length) await admin.from("price_snapshots").upsert(snaps, { ignoreDuplicates: true });
  return toWrite.length;
}
