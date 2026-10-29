import { NextResponse } from "next/server";
import { ebaySales } from "@/lib/pricing/ebay";
import { errorResponse } from "@/lib/server/http";
import { allowRequest, clientKey } from "@/lib/server/rate-limit";

/**
 * Recent eBay sold listings for a TCG API card. Public market data, so the
 * CDN keeps it for 12 hours: one upstream call serves everyone looking.
 */
export async function GET(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const productId = decodeURIComponent(id);
  if (!productId.startsWith("tcgapi:")) return NextResponse.json({ ebay: null });
  if (!allowRequest(clientKey(req, "ebay"), 20, 20)) {
    return NextResponse.json({ error: { code: "rate_limited", message: "Too many requests." } }, { status: 429 });
  }
  const printing = new URL(req.url).searchParams.get("printing") || null;
  try {
    const ebay = await ebaySales(productId.slice("tcgapi:".length), printing);
    return NextResponse.json({ ebay }, { headers: { "Cache-Control": "public, s-maxage=43200, stale-while-revalidate=86400" } });
  } catch (err) {
    return errorResponse(err);
  }
}
