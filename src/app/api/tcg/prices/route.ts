import { NextResponse } from "next/server";
import { providerFor } from "@/lib/pricing";
import { mapLimit } from "@/lib/pricing/cache";
import { PricingUnavailableError } from "@/lib/pricing/types";
import { errorResponse } from "@/lib/server/http";
import { allowRequest, clientKey } from "@/lib/server/rate-limit";
import type { NormalizedPrice } from "@/lib/types";
import { priceToRow } from "@/lib/supabase/mappers";
import { getAdminSupabase, getServerSupabase } from "@/lib/supabase/server";

const MAX_IDS = 60;

/**
 * Current prices for a list of product ids. Each product is cached for an
 * hour and concurrent requests are deduplicated, so refreshing a collection
 * costs at most one upstream call per product per hour.
 */
export async function POST(req: Request) {
  if (!allowRequest(clientKey(req, "prices"), 10, 10)) {
    return NextResponse.json({ error: { code: "rate_limited", message: "Too many refreshes." } }, { status: 429 });
  }
  let ids: string[];
  try {
    const body = await req.json();
    ids = Array.isArray(body?.ids) ? [...new Set<string>(body.ids.filter((x: unknown) => typeof x === "string"))].slice(0, MAX_IDS) : [];
  } catch {
    return NextResponse.json({ error: { code: "bad_request", message: "Invalid body." } }, { status: 400 });
  }
  try {
    const prices: NormalizedPrice[] = [];
    const failed: { id: string; code: string }[] = [];
    let stop: PricingUnavailableError | null = null;
    await mapLimit(ids, 3, async (id) => {
      if (stop) return failed.push({ id, code: stop.code });
      try {
        const { provider, externalId } = providerFor(id);
        prices.push(...(await provider.getPrices(externalId)));
      } catch (err) {
        if (err instanceof PricingUnavailableError) {
          if (err.code === "rate_limited" || err.code === "not_configured" || err.code === "auth") stop = err;
          failed.push({ id, code: err.code });
        } else failed.push({ id, code: "upstream" });
      }
    });
    if (stop && !prices.length) throw stop;
    await persist(prices);
    return NextResponse.json({ prices, failed });
  } catch (err) {
    return errorResponse(err);
  }
}

/** For signed-in users, keep the shared price tables current as a side effect. */
async function persist(prices: NormalizedPrice[]) {
  const admin = getAdminSupabase();
  const userClient = await getServerSupabase();
  if (!admin || !userClient || !prices.length) return;
  const { data } = await userClient.auth.getUser();
  if (!data.user) return;
  const today = new Date().toISOString().slice(0, 10);
  // Only products already in the catalog (imported via /api/catalog).
  const ids = [...new Set(prices.map((p) => p.productId))];
  const { data: known } = await admin.from("products").select("id").in("id", ids);
  const knownIds = new Set((known ?? []).map((r) => r.id));
  const rows = prices.filter((p) => knownIds.has(p.productId));
  if (!rows.length) return;
  await admin.from("product_prices").upsert(rows.map(priceToRow));
  const snaps = rows
    .filter((p) => p.market !== null)
    .map((p) => ({ product_id: p.productId, printing: p.printing ?? "", snapshot_date: today, market_price: p.market as number, source: p.source }));
  if (snaps.length) await admin.from("price_snapshots").upsert(snaps);
}
