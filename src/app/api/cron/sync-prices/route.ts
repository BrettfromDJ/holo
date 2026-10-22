import { NextResponse } from "next/server";
import { computeTimeline } from "@/lib/finance/portfolio";
import { providerFor } from "@/lib/pricing";
import { mapLimit } from "@/lib/pricing/cache";
import { bulkPrices, isTcgApiConfigured } from "@/lib/pricing/tcgapi";
import { PricingUnavailableError } from "@/lib/pricing/types";
import { loadCollection } from "@/lib/supabase/load";
import { priceToRow } from "@/lib/supabase/mappers";
import { getAdminSupabase } from "@/lib/supabase/server";
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

  // --- 2. Fetch prices -------------------------------------------------------
  const prices: NormalizedPrice[] = [];
  const failures: { id: string; reason: string }[] = [];
  let mode: "bulk" | "per-product" = "per-product";
  try {
    const bulk = productIds.length ? await bulkPrices(productIds.map((id) => id.slice("tcgapi:".length))) : [];
    if (bulk) {
      prices.push(...bulk);
      mode = "bulk";
    }
  } catch (err) {
    failures.push({ id: "bulk", reason: err instanceof Error ? err.message : "bulk failed" });
  }
  if (mode === "per-product") {
    let halted = false;
    await mapLimit(productIds, 2, async (id) => {
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
  if (prices.length) {
    const { error } = await admin.from("product_prices").upsert(prices.map(priceToRow));
    if (error) failures.push({ id: "product_prices", reason: error.message });
    const snaps = prices
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

  return NextResponse.json({ date: today, mode, products: productIds.length, pricesStored: prices.length, usersUpdated, failures });
}

function round(n: number) {
  return Math.round(n * 100) / 100;
}
