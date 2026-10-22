import { NextResponse } from "next/server";
import { providerFor } from "@/lib/pricing";
import { errorResponse } from "@/lib/server/http";
import { allowRequest, clientKey } from "@/lib/server/rate-limit";

/** Product details plus current price for every printing. */
export async function GET(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  if (!allowRequest(clientKey(req, "product"), 60, 60)) {
    return NextResponse.json({ error: { code: "rate_limited", message: "Too many requests." } }, { status: 429 });
  }
  try {
    const { provider, externalId } = providerFor(decodeURIComponent(id));
    const [product, prices] = await Promise.all([provider.getProduct(externalId), provider.getPrices(externalId)]);
    product.printings = prices.map((p) => p.printing).filter((p): p is string => Boolean(p));
    return NextResponse.json({ product, prices });
  } catch (err) {
    return errorResponse(err);
  }
}
