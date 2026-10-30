import { NextResponse } from "next/server";
import { tcgApiProvider } from "@/lib/pricing";
import { FRANCHISES, type GameFilter, type ProductTypeFilter } from "@/lib/pricing/types";
import { dbCached, overLimit, takeQuota } from "@/lib/server/api-cache";
import { errorResponse } from "@/lib/server/http";
import { allowRequest, clientKey } from "@/lib/server/rate-limit";

export async function GET(req: Request) {
  const url = new URL(req.url);
  const q = (url.searchParams.get("q") ?? "").trim().slice(0, 100);
  const type = (url.searchParams.get("type") ?? "all") as ProductTypeFilter;
  const game = (url.searchParams.get("game") ?? "pokemon") as GameFilter;
  const page = Math.max(1, Number(url.searchParams.get("page") ?? 1) || 1);
  if (q.length < 2) return NextResponse.json({ hits: [], total: 0, hasMore: false });
  if (game !== "all" && !FRANCHISES.some((f) => f.value === game)) return NextResponse.json({ error: { code: "bad_request", message: "Invalid game." } }, { status: 400 });
  if (!["all", "cards", "sealed"].includes(type)) return NextResponse.json({ error: { code: "bad_request", message: "Invalid type." } }, { status: 400 });
  if (!allowRequest(clientKey(req, "search"), 40, 40)) {
    return NextResponse.json({ error: { code: "rate_limited", message: "Searching too quickly — try again in a moment." } }, { status: 429 });
  }
  try {
    // Asked today already (by anyone): free. Otherwise it counts toward the person's daily limit.
    const key = `live-search:${game}:${type}:${page}:${q.toLowerCase()}`;
    const result = await dbCached(key, async () => {
      if (!(await takeQuota(req, "liveSearch"))) throw new LimitReached();
      return tcgApiProvider.search({ q, type, game, page });
    });
    return NextResponse.json(result);
  } catch (err) {
    if (err instanceof LimitReached) return NextResponse.json(overLimit("live catalog searches"), { status: 429 });
    return errorResponse(err);
  }
}

class LimitReached extends Error {}
