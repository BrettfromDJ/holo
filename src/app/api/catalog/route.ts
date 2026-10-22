import { NextResponse } from "next/server";
import { providerFor } from "@/lib/pricing";
import { PricingUnavailableError } from "@/lib/pricing/types";
import { errorResponse } from "@/lib/server/http";
import { allowRequest, clientKey } from "@/lib/server/rate-limit";
import { getAdminSupabase, getServerSupabase } from "@/lib/supabase/server";
import { priceToRow, productToRow } from "@/lib/supabase/mappers";
import type { PricePoint } from "@/lib/types";

/**
 * Import a product into the catalog before it's added to a collection or
 * watchlist. The server re-fetches the product from the pricing source by id,
 * so clients can never write arbitrary catalog data. Returns the product,
 * current prices and whatever price history the subscription allows.
 */
export async function POST(req: Request) {
  if (!allowRequest(clientKey(req, "catalog"), 20, 20)) {
    return NextResponse.json({ error: { code: "rate_limited", message: "Too many requests." } }, { status: 429 });
  }
  let productId: string;
  let printing: string | null;
  try {
    const body = await req.json();
    productId = String(body?.productId ?? "");
    printing = typeof body?.printing === "string" && body.printing ? body.printing : null;
  } catch {
    return NextResponse.json({ error: { code: "bad_request", message: "Invalid body." } }, { status: 400 });
  }

  try {
    const { provider, externalId } = providerFor(productId);
    const [product, prices] = await Promise.all([provider.getProduct(externalId), provider.getPrices(externalId)]);
    product.printings = prices.map((p) => p.printing).filter((p): p is string => Boolean(p));

    let history: PricePoint[] = [];
    let historyAvailable = true;
    let historyReason: string | undefined;
    try {
      const h = await provider.getHistory(externalId, printing ?? prices[0]?.printing ?? null, "all");
      history = h.points;
      historyAvailable = h.available;
      historyReason = h.reason;
    } catch (err) {
      historyAvailable = false;
      historyReason = err instanceof PricingUnavailableError ? err.message : "History unavailable.";
    }

    // Persist to the shared catalog when signed in and the service role is configured.
    const userClient = await getServerSupabase();
    const user = userClient ? (await userClient.auth.getUser()).data.user : null;
    const admin = getAdminSupabase();
    if (user && admin) {
      await admin.from("products").upsert(productToRow(product));
      if (prices.length) await admin.from("product_prices").upsert(prices.map(priceToRow));
      const histPrinting = printing ?? prices[0]?.printing ?? "";
      if (history.length) {
        await admin.from("price_snapshots").upsert(
          history.map((p) => ({ product_id: product.id, printing: histPrinting ?? "", snapshot_date: p.date, market_price: p.price, source: provider.source })),
          { ignoreDuplicates: true },
        );
      }
    }

    return NextResponse.json({ product, prices, history, historyAvailable, historyReason: historyReason ?? null });
  } catch (err) {
    return errorResponse(err);
  }
}
