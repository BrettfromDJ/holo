import { NextResponse } from "next/server";
import { ebaySummaries } from "@/lib/pricing/ebay";
import { errorResponse } from "@/lib/server/http";
import { allowRequest, clientKey } from "@/lib/server/rate-limit";

/**
 * eBay summaries for many cards at once (`?ids=tcgapi:1,tcgapi:2`), for lists
 * like Worth grading. One bulk call upstream; cached 12 hours at the CDN.
 */
export async function GET(req: Request) {
  if (!allowRequest(clientKey(req, "ebay-bulk"), 10, 10)) {
    return NextResponse.json({ error: { code: "rate_limited", message: "Too many requests." } }, { status: 429 });
  }
  const ids = (new URL(req.url).searchParams.get("ids") ?? "")
    .split(",")
    .filter((id) => /^tcgapi:\d+$/.test(id))
    .map((id) => id.slice("tcgapi:".length))
    .slice(0, 1000);
  if (!ids.length) return NextResponse.json({ ebay: {} });
  try {
    const byId = await ebaySummaries(ids);
    const ebay = Object.fromEntries(Object.entries(byId).map(([id, rows]) => [`tcgapi:${id}`, rows]));
    return NextResponse.json({ ebay }, { headers: { "Cache-Control": "public, s-maxage=43200, stale-while-revalidate=86400" } });
  } catch (err) {
    return errorResponse(err);
  }
}
