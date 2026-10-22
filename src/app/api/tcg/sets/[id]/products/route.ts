import { NextResponse } from "next/server";
import { tcgApiProvider } from "@/lib/pricing";
import type { ProductTypeFilter } from "@/lib/pricing/types";
import { errorResponse } from "@/lib/server/http";
import { allowRequest, clientKey } from "@/lib/server/rate-limit";

/** Every product in a set (cards, sealed or both), most valuable first. */
export async function GET(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const type = (new URL(req.url).searchParams.get("type") ?? "all") as ProductTypeFilter;
  if (!/^\d+$/.test(id) || !["all", "cards", "sealed"].includes(type)) {
    return NextResponse.json({ error: { code: "bad_request", message: "Invalid set or type." } }, { status: 400 });
  }
  if (!allowRequest(clientKey(req, "set-products"), 30, 30)) {
    return NextResponse.json({ error: { code: "rate_limited", message: "Too many requests." } }, { status: 429 });
  }
  try {
    return NextResponse.json({ hits: await tcgApiProvider.setProducts(id, type) });
  } catch (err) {
    return errorResponse(err);
  }
}
