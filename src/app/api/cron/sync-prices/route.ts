import { NextResponse } from "next/server";
import { priceFromRow } from "@/lib/supabase/mappers";
import { computeTimeline } from "@/lib/finance/portfolio";
import { providerFor } from "@/lib/pricing";
import { mapLimit } from "@/lib/pricing/cache";
import { bulkPrices, isTcgApiConfigured } from "@/lib/pricing/tcgapi";
import { PricingUnavailableError } from "@/lib/pricing/types";
import { loadCollection } from "@/lib/supabase/load";
import { priceToRow } from "@/lib/supabase/mappers";
import { getAdminSupabase } from "@/lib/supabase/server";
import { sendPriceAlerts } from "@/lib/server/price-alerts";
import type { NormalizedPrice } from "@/lib/types";

export const dynamic = "force-dynamic";
export const maxDuration = 300;

/**
 * Daily price sync (Vercel Cron, see vercel.json).
 *
 * 1. Collect every product that is owned or watched by any user.
 * 2. Fetch current prices — one bulk call on Pro+, otherwise one call per
 *    product with low concurrency, stopping early if the daily limit is hit.
 * 3. Store current prices and today's price snapshot.
 * 4. Rebuild each user's daily portfolio snapshots from stored prices.
 * 5. Push a notification for watched cards at or below their target price.
 */
export async function GET(req: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret || req.headers.get("authorization") !== `Bearer ${secret}`) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ error: "Supabase service role is not configured." }, { status: 503 });
  if (!isTcgApiConfigured()) return NextResponse.json({ error: "TCG API key is not configured." }, { status: 503 });

  const today = new Date().toISOString().slice(0, 10);
  const [{ data: holdings, error: hErr }, { data: watch, error: wErr }] = await Promise.all([
    admin.from("holdings").select("product_id, user_id"),
    admin.from("watchlist_items").select("product_id, user_id"),
  ]);
  if (hErr || wErr) return NextResponse.json({ error: (hErr ?? wErr)?.message }, { status: 500 });

  const productIds = [...new Set([...(holdings ?? []), ...(watch ?? [])].map((r) => r.product_id))].filter((id) => id.startsWith("tcgapi:"));
  const userIds = [...new Set([...(holdings ?? []), ...(watch ?? [])].map((r) => r.user_id))];

  // --- 2. Prices: reuse the catalog refresh's, fetch only what it missed ------
  // The nightly catalog refresh already prices every set daily, so a price stored in the last
  // 30 hours is used as is (no API call); only older or missing ones are fetched here.
  const failures: { id: string; reason: string }[] = [];
  const reused: NormalizedPrice[] = [];
  const freshIds = new Set<string>();
  for (let i = 0; i < productIds.length; i += 300) {
    const { data } = await admin
      .from("product_prices")
      .select("*")
      .in("product_id", productIds.slice(i, i + 300))
      .gte("fetched_at", new Date(Date.now() - 30 * 60 * 60 * 1000).toISOString());
    for (const r of data ?? []) {
      reused.push(priceFromRow(r));
      freshIds.add(r.product_id);
    }
  }
  const toFetch = productIds.filter((id) => !freshIds.has(id));
  const prices: NormalizedPrice[] = [];
  let mode: "bulk" | "per-product" | "reused" = toFetch.length ? "per-product" : "reused";
  try {
    const bulk = toFetch.length ? await bulkPrices(toFetch.map((id) => id.slice("tcgapi:".length))) : [];
    if (bulk) {
      prices.push(...bulk);
      mode = "bulk";
    }
  } catch (err) {
    failures.push({ id: "bulk", reason: err instanceof Error ? err.message : "bulk failed" });
  }
  if (mode === "per-product") {
    let halted = false;
    await mapLimit(toFetch, 2, async (id) => {
      if (halted) return failures.push({ id, reason: "skipped: rate limit" });
      try {
        const { provider, externalId } = providerFor(id);
        prices.push(...(await provider.getPrices(externalId)));
      } catch (err) {
        if (err instanceof PricingUnavailableError && err.code === "rate_limited") halted = true;
        failures.push({ id, reason: err instanceof Error ? err.message : "failed" });
      }
    });
  }

  // --- 3. Store prices & snapshots -----------------------------------------
  if (prices.length || reused.length) {
    // A blank never replaces a known price (e.g. PriceCharting's, for cards TCGplayer doesn't price).
    const blankIds = [...new Set(prices.filter((p) => p.market === null).map((p) => p.productId))];
    const known = new Set<string>();
    for (let i = 0; i < blankIds.length; i += 300) {
      const { data } = await admin.from("product_prices").select("product_id, printing").in("product_id", blankIds.slice(i, i + 300)).not("market_price", "is", null);
      for (const r of data ?? []) known.add(`${r.product_id}|${r.printing}`);
    }
    const rows = prices.map(priceToRow).filter((r) => !(r.market_price === null && known.has(`${r.product_id}|${r.printing}`)));
    if (rows.length) {
      const { error } = await admin.from("product_prices").upsert(rows);
      if (error) failures.push({ id: "product_prices", reason: error.message });
    }
    const snaps = [...reused, ...prices]
      .filter((p) => p.market !== null)
      .map((p) => ({ product_id: p.productId, printing: p.printing ?? "", snapshot_date: today, market_price: p.market as number, source: p.source }));
    if (snaps.length) {
      const { error: sErr } = await admin.from("price_snapshots").upsert(snaps);
      if (sErr) failures.push({ id: "price_snapshots", reason: sErr.message });
    }
  }

  // --- 4. Portfolio snapshots ----------------------------------------------
  let usersUpdated = 0;
  for (const userId of userIds) {
    try {
      const data = await loadCollection(admin, userId);
      const timeline = computeTimeline(data, today);
      const rows = timeline.map((p) => ({
        user_id: userId,
        snapshot_date: p.date,
        market_value: round(p.value),
        cost_basis: round(p.costBasis),
        unrealized: round(p.unrealized),
        market_gain: round(p.marketGain),
        daily_return: p.dailyReturn,
        twr_index: p.twrIndex,
        invested: round(p.invested),
        proceeds: round(p.proceeds),
        unpriced_count: p.unpricedHoldings,
      }));
      for (let i = 0; i < rows.length; i += 500) {
        const { error } = await admin.from("portfolio_snapshots").upsert(rows.slice(i, i + 500));
        if (error) throw error;
      }
      usersUpdated++;
    } catch (err) {
      failures.push({ id: `user:${userId}`, reason: err instanceof Error ? err.message : "snapshot failed" });
    }
  }

  // --- 5. Price alerts -------------------------------------------------------
  let alerts: Awaited<ReturnType<typeof sendPriceAlerts>> | { error: string };
  try {
    alerts = await sendPriceAlerts(admin, [...reused, ...prices]);
  } catch (err) {
    alerts = { error: err instanceof Error ? err.message : "alerts failed" };
  }

  return NextResponse.json({ date: today, mode, products: productIds.length, reused: reused.length, fetched: toFetch.length, pricesStored: prices.length, usersUpdated, alerts, failures });
}

function round(n: number) {
  return Math.round(n * 100) / 100;
}
