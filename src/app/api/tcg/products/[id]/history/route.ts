import { NextResponse } from "next/server";
import { providerFor } from "@/lib/pricing";
import { errorResponse } from "@/lib/server/http";
import { allowRequest, clientKey } from "@/lib/server/rate-limit";

const RANGES = ["month", "quarter", "year", "all"] as const;

/** Historical market prices, windowed by the API subscription tier. */
export async function GET(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const url = new URL(req.url);
  const printing = url.searchParams.get("printing") || null;
  const range = (url.searchParams.get("range") ?? "all") as (typeof RANGES)[number];
  if (!RANGES.includes(range)) return NextResponse.json({ error: { code: "bad_request", message: "Invalid range." } }, { status: 400 });
  if (!allowRequest(clientKey(req, "history"), 60, 60)) {
    return NextResponse.json({ error: { code: "rate_limited", message: "Too many requests." } }, { status: 429 });
  }
  try {
    const { provider, externalId } = providerFor(decodeURIComponent(id));
    return NextResponse.json(await provider.getHistory(externalId, printing, range));
  } catch (err) {
    return errorResponse(err);
  }
}
