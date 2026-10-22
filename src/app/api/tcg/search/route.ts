import { NextResponse } from "next/server";
import { tcgApiProvider } from "@/lib/pricing";
import type { ProductTypeFilter } from "@/lib/pricing/types";
import { errorResponse } from "@/lib/server/http";
import { allowRequest, clientKey } from "@/lib/server/rate-limit";

export async function GET(req: Request) {
  const url = new URL(req.url);
  const q = (url.searchParams.get("q") ?? "").trim().slice(0, 100);
  const type = (url.searchParams.get("type") ?? "all") as ProductTypeFilter;
  const page = Math.max(1, Number(url.searchParams.get("page") ?? 1) || 1);
  if (q.length < 2) return NextResponse.json({ hits: [], total: 0, hasMore: false });
  if (!["all", "cards", "sealed"].includes(type)) return NextResponse.json({ error: { code: "bad_request", message: "Invalid type." } }, { status: 400 });
  if (!allowRequest(clientKey(req, "search"), 40, 40)) {
    return NextResponse.json({ error: { code: "rate_limited", message: "Searching too quickly — try again in a moment." } }, { status: 429 });
  }
  try {
    return NextResponse.json(await tcgApiProvider.search({ q, type, page }));
  } catch (err) {
    return errorResponse(err);
  }
}
