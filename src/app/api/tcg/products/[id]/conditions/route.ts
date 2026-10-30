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
  const printing = new URL(req.url).searchParams.get("printing") || null;
  try {
    // Shared for a day across every server.
    const conditions = await dbCached(`conditions:${productId}:${printing ?? ""}`, () => conditionPrices(productId.slice("tcgapi:".length), printing));
    return NextResponse.json({ conditions }, { headers: { "Cache-Control": "public, s-maxage=43200, stale-while-revalidate=86400" } });
  } catch (err) {
    return errorResponse(err);
  }
}
