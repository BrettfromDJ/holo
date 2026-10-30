import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import { catalogGameList, gameSetsPage, setProductsPage } from "../pricing/tcgapi";
import { PricingUnavailableError } from "../pricing/types";
import type { CatalogSetRow, Database } from "../supabase/database.types";
import { priceToRow, productToRow } from "../supabase/mappers";
import type { NormalizedPrice } from "../types";

const DAY = 24 * 60 * 60 * 1000;
const HOUR_MS = 60 * 60 * 1000;

export interface CatalogSyncOptions {
  /** Most TCG API requests this run may make. A real 429 also stops it. */
  maxCalls: number;
  /** Most requests all of today's runs together may make (counted in catalog_sync_usage). */
  dailyCalls?: number;
}

export interface CatalogSyncResult {
  calls: number;
  setsListed: number;
  setsSynced: string[];
  productsSeen: number;
  pricesStored: number;
  stoppedBecause: "done" | "budget" | "daily_budget" | "time" | "rate_limited" | "error";
  error?: string;
}

/** A set's prices count as fresh for this long; after that it's refreshed (so, daily). */
export const SET_FRESH_MS = 20 * HOUR_MS;
/** Stop a run with this much of Vercel's 300-second limit left. */
const RUN_MS = 250_000;

/** Calls the catalog refresh has made today (all runs together). */
export async function catalogCallsToday(admin: SupabaseClient<Database>): Promise<number> {
  const today = new Date().toISOString().slice(0, 10);
  const { data } = await admin.from("catalog_sync_usage").select("calls").eq("day", today).maybeSingle();
  return data?.calls ?? 0;
}

export async function recordCatalogCalls(admin: SupabaseClient<Database>, calls: number): Promise<void> {
  if (!calls) return;
  const today = new Date().toISOString().slice(0, 10);
  const used = await catalogCallsToday(admin);
  await admin.from("catalog_sync_usage").upsert({ day: today, calls: used + calls });
}

type QueuedSet = { slug: string; tcgapi_id: number; name: string; products_synced_at: string | null; game_slug: string; release_date: string | null };

/**
 * Load (or refresh) one set's products and prices, a page of 200 at a time. Very large sets
 * stop at 25 pages (5,000 products) and still count as loaded, so they can't hog the queue.
 * Returns false when `canCall` ran out before the set was finished.
 */
export async function refreshSet(
  admin: SupabaseClient<Database>,
  set: Pick<QueuedSet, "slug" | "tcgapi_id" | "name">,
  canCall: () => boolean,
  onCall: () => void,
  result?: CatalogSyncResult,
): Promise<boolean> {
  let count = 0;
  for (let page = 1; page <= 25; page++) {
    if (!canCall()) return false;
    onCall();
    const { products, prices, hasMore } = await setProductsPage({ id: set.tcgapi_id, slug: set.slug, name: set.name }, page);
    count += products.length;
    if (result) result.productsSeen += products.length;
    if (products.length) {
      const { error } = await admin.from("products").upsert(products.map(productToRow), { onConflict: "id", ignoreDuplicates: true });
      if (error) throw new Error(error.message);
      const stored = await storePrices(admin, prices);
      if (result) result.pricesStored += stored;
    }
    if (!hasMore || page === 25) break;
  }
  const { error } = await admin.from("catalog_sets").update({ products_synced_at: new Date().toISOString(), product_count: count }).eq("slug", set.slug);
  if (error) throw new Error(error.message);
  return true;
}

/**
 * Keeps the Explore catalog's prices current so browsing never touches the TCG API:
 *
 * 1. Once a week, refresh the list of sets for every catalog (a few calls).
 * 2. Load sets that have never been loaded, then refresh every set whose prices are older
 *    than SET_FRESH_MS: Pokémon first, then every other brand, stalest first. So every
 *    set's prices are refreshed daily while the budget allows.
 *
 * A run stops at `maxCalls`, near Vercel's time limit, or when today's calls (all runs
 * together) reach `dailyCalls`. The cron route chains runs until the day's work is done.
 * Products are inserted but never overwritten, so a type the user corrected stays corrected.
 */
export async function syncCatalog(admin: SupabaseClient<Database>, opts: CatalogSyncOptions): Promise<CatalogSyncResult> {
  const result = await runCatalogSync(admin, opts);
  await recordCatalogCalls(admin, result.calls).catch(() => {});
  return result;
}

async function runCatalogSync(admin: SupabaseClient<Database>, opts: CatalogSyncOptions): Promise<CatalogSyncResult> {
  const result: CatalogSyncResult = { calls: 0, setsListed: 0, setsSynced: [], productsSeen: 0, pricesStored: 0, stoppedBecause: "done" };
  const started = Date.now();
  const usedToday = opts.dailyCalls ? await catalogCallsToday(admin) : 0;
  let stop: CatalogSyncResult["stoppedBecause"] | null = null;
  // The "remaining" figure TCG API reports doesn't always match its dashboard, so it never
  // blocks the sync; our own per-run, per-day and time limits and a real 429 do.
  const canCall = () => {
    if (result.calls >= opts.maxCalls) stop = "budget";
    else if (opts.dailyCalls && usedToday + result.calls >= opts.dailyCalls) stop = "daily_budget";
    else if (Date.now() - started > RUN_MS) stop = "time";
    else return true;
    return false;
  };

  try {
    // --- 0. Brands (weekly; never blocks the rest) -------------------------
    await syncGames(admin);
    // --- 1. Set lists (weekly per brand; a newly added brand right away) --
    for (const game of await catalogGameList()) {
      const { data: newest } = await admin.from("catalog_sets").select("listed_at").eq("game_slug", game.slug).order("listed_at", { ascending: false }).limit(1);
      if (newest?.length && Date.now() - Date.parse(newest[0].listed_at) < 7 * DAY) continue;
      // Collect every page first and save at the end: a brand only counts as
      // listed once its whole list is in, so a listing cut short by the budget
      // is redone on the next run instead of being skipped for a week.
      const rows: Database["public"]["Tables"]["catalog_sets"]["Insert"][] = [];
      for (let page = 1; page <= 20; page++) {
        if (!canCall()) return { ...result, stoppedBecause: "budget" };
        result.calls++;
        const { sets, hasMore } = await gameSetsPage(game.slug, page);
        rows.push(
          ...sets.map((s) => ({
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
          })),
        );
        if (!hasMore) break;
      }
      for (let i = 0; i < rows.length; i += 500) {
        const { error } = await admin.from("catalog_sets").upsert(rows.slice(i, i + 500));
        if (error) throw new Error(error.message);
      }
      result.setsListed += rows.length;
    }

    // --- 2. Products: unloaded sets, then Pokémon, then everything else ---
    const { data: queue, error: qErr } = await admin
      .from("catalog_sets")
      .select("slug, tcgapi_id, name, products_synced_at, game_slug, release_date")
      .limit(20000);
    if (qErr) throw new Error(qErr.message);
    const now = Date.now();
    const age = (s: QueuedSet) => (s.products_synced_at ? now - Date.parse(s.products_synced_at) : Infinity);
    const tier = (s: QueuedSet) => (!s.products_synced_at ? 0 : /pokemon/i.test(s.game_slug) ? 1 : 2);
    const due = ((queue ?? []) as QueuedSet[])
      .filter((s) => age(s) >= SET_FRESH_MS)
      .sort((a, b) => tier(a) - tier(b) || (tier(a) === 0 ? (b.release_date ?? "").localeCompare(a.release_date ?? "") : age(b) - age(a)));

    for (const set of due) {
      const finished = await refreshSet(admin, set, canCall, () => result.calls++, result);
      if (!finished) break;
      result.setsSynced.push(set.slug);
    }
    return { ...result, stoppedBecause: stop ?? "done" };
  } catch (err) {
    if (err instanceof PricingUnavailableError && err.code === "rate_limited") return { ...result, stoppedBecause: "rate_limited" };
    return { ...result, stoppedBecause: "error", error: err instanceof Error ? err.message : String(err) };
  }
}

/** Store prices, skipping products priced in the last 20 hours (by the daily price sync). */
async function storePrices(admin: SupabaseClient<Database>, prices: NormalizedPrice[]): Promise<number> {
  const rows = prices.map(priceToRow);
  const ids = [...new Set(rows.map((r) => r.product_id))];
  const { data: existing } = await admin.from("product_prices").select("product_id, fetched_at").in("product_id", ids);
  const fresh = new Set((existing ?? []).filter((r) => Date.now() - Date.parse(r.fetched_at) < SET_FRESH_MS).map((r) => r.product_id));
  const toWrite = rows.filter((r) => !fresh.has(r.product_id));
  if (!toWrite.length) return 0;
  const { error } = await admin.from("product_prices").upsert(toWrite);
  if (error) throw new Error(error.message);
  // No daily snapshots here: across every brand that would be hundreds of
  // thousands of rows per pass. History comes from the daily price sync for
  // owned/watched products and from "Load full price history" on demand.
  return toWrite.length;
}

/** Store the catalogs (brands) with their logos for Explore. Missing table or errors are ignored. */
async function syncGames(admin: SupabaseClient<Database>) {
  try {
    const { data, error } = await admin.from("catalog_games").select("slug, listed_at");
    if (error) return;
    const games = await catalogGameList();
    const stored = new Set((data ?? []).map((g) => g.slug));
    const newest = (data ?? []).reduce((m, g) => Math.max(m, Date.parse(g.listed_at)), 0);
    if (games.every((g) => stored.has(g.slug)) && Date.now() - newest < 7 * DAY) return;
    await admin.from("catalog_games").upsert(
      games.map((g, i) => ({
        slug: g.slug,
        name: g.name,
        logo_url: g.logoUrl,
        image_url: g.imageUrl,
        set_count: g.setCount,
        card_count: g.cardCount,
        sort: i,
        listed_at: new Date().toISOString(),
      })),
    );
  } catch {
    // Brands are cosmetic; Explore falls back to names from the set list.
  }
}

/** Sets refreshed on demand recently on this server, so a burst of views makes one refresh. */
const refreshing = new Map<string, number>();

/**
 * Someone opened a set (or a card in it) whose prices are more than a day old: refresh that
 * set now, in the background, if today's catalog budget allows. Costs one or two requests.
 */
export async function refreshSetIfStale(
  admin: SupabaseClient<Database>,
  set: Pick<CatalogSetRow, "slug" | "tcgapi_id" | "name" | "products_synced_at">,
): Promise<void> {
  if (set.products_synced_at && Date.now() - Date.parse(set.products_synced_at) < SET_FRESH_MS) return;
  if (Date.now() - (refreshing.get(set.slug) ?? 0) < 10 * 60 * 1000) return;
  refreshing.set(set.slug, Date.now());
  const daily = Number(process.env.CATALOG_SYNC_DAILY_CALLS) || 7000;
  const used = await catalogCallsToday(admin);
  let calls = 0;
  try {
    await refreshSet(admin, set, () => used + calls < daily && calls < 25, () => calls++);
  } finally {
    await recordCatalogCalls(admin, calls).catch(() => {});
  }
}
