import { NextResponse } from "next/server";
import { conditionPrices } from "@/lib/pricing/tcgapi";
import { dbCached } from "@/lib/server/api-cache";
import { errorResponse } from "@/lib/server/http";
import { allowRequest, clientKey } from "@/lib/server/rate-limit";

/** TCGplayer prices per condition for a card (Pro+). Public market data, cached 12 hours at the CDN. */
export async function GET(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const productId = decodeURIComponent((await ctx.params).id);
  if (!productId.startsWith("tcgapi:")) return NextResponse.json({ conditions: [] });
  if (!allowRequest(clientKey(req, "conditions"), 30, 30)) {
    return NextResponse.json({ error: { code: "rate_limited", message: "Too many requests." } }, { status: 429 });
  }
  try {
    // Every printing at once: the app and website pick the printing they show (falling back to
    // another when names differ), so a mismatched printing name never comes back empty.
    // Shared for a day across every server; an empty answer only for an hour, so a card whose
    // condition prices weren't ready yet is asked again soon.
    const conditions = await dbCached(`conditions:${productId}:all`, () => conditionPrices(productId.slice("tcgapi:".length), null), (rows) =>
      rows.some((r) => r.price !== null) ? 24 * 60 * 60 * 1000 : 60 * 60 * 1000,
    );
    return NextResponse.json({ conditions }, { headers: { "Cache-Control": "public, s-maxage=43200, stale-while-revalidate=86400" } });
  } catch (err) {
    return errorResponse(err);
  }
}
