import { NextResponse } from "next/server";
import { providerFor } from "@/lib/pricing";
import { errorResponse } from "@/lib/server/http";
import { allowRequest, clientKey } from "@/lib/server/rate-limit";
import { getAdminSupabase } from "@/lib/supabase/server";

/** Below this many stored days, a product's history is fetched from TCG API (once). */
const ENOUGH_DAYS = 60;

/**
 * POST /api/explore/products/<id>/history { printing } — full price history.
 * Served from storage when enough is already saved; otherwise fetched from
 * TCG API once (one request) and saved permanently, so later views are free.
 */
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  if (!allowRequest(clientKey(req, "history"), 10, 10)) {
    return NextResponse.json({ error: { code: "rate_limited", message: "Too many requests — try again in a minute." } }, { status: 429 });
  }
  const id = decodeURIComponent((await params).id);
  const body = await req.json().catch(() => null);
  const printing: string | null = typeof body?.printing === "string" && body.printing ? body.printing : null;
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ error: { message: "Supabase isn't configured." } }, { status: 503 });

  const stored = async () => {
    const { data } = await admin
      .from("price_snapshots")
      .select("snapshot_date, market_price")
      .eq("product_id", id)
      .eq("printing", printing ?? "")
      .order("snapshot_date")
      .limit(5000);
    return (data ?? []).map((s) => ({ date: s.snapshot_date, price: Number(s.market_price) }));
  };

  try {
    const existing = await stored();
    if (existing.length >= ENOUGH_DAYS) return NextResponse.json({ points: existing, available: true, fetched: false });

    const { data: product } = await admin.from("products").select("id").eq("id", id).maybeSingle();
    if (!product) return NextResponse.json({ error: { message: "Not in the catalog." } }, { status: 404 });

    const { provider, externalId } = providerFor(id);
    const h = await provider.getHistory(externalId, printing, "all");
    if (h.points.length) {
      await admin.from("price_snapshots").upsert(
        h.points.map((p) => ({ product_id: id, printing: printing ?? "", snapshot_date: p.date, market_price: p.price, source: provider.source })),
        { ignoreDuplicates: true },
      );
    }
    return NextResponse.json({ points: await stored(), available: h.available, reason: h.reason ?? null, fetched: true });
  } catch (err) {
    return errorResponse(err);
  }
}
