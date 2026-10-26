import { NextResponse } from "next/server";
import { productFromRow, priceFromRow } from "@/lib/supabase/mappers";
import { getAdminSupabase } from "@/lib/supabase/server";
import { priceKey, type PricePoint } from "@/lib/types";

/**
 * GET /api/explore/products/<id> — a catalog product for the full product
 * page, read entirely from Supabase (no TCG API requests): details, stored
 * prices per printing, and whatever daily price history has been stored.
 */
export async function GET(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const id = decodeURIComponent((await params).id);
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ error: { message: "Explore needs Supabase to be configured." } }, { status: 503 });
  const { data: row } = await admin.from("products").select("*").eq("id", id).maybeSingle();
  if (!row) return NextResponse.json({ error: { message: "Not in the catalog." } }, { status: 404 });

  const [{ data: priceRows }, { data: snaps }] = await Promise.all([
    admin.from("product_prices").select("*").eq("product_id", id),
    admin.from("price_snapshots").select("printing, snapshot_date, market_price").eq("product_id", id).order("snapshot_date").limit(5000),
  ]);
  const prices = (priceRows ?? []).map(priceFromRow);
  const product = productFromRow(row);
  // The page picks the first printing, so list priced printings first.
  const printings = [...new Set([...prices.filter((p) => p.market !== null), ...prices].map((p) => p.printing).filter((p): p is string => Boolean(p)))];
  if (printings.length) product.printings = printings;

  const history: Record<string, PricePoint[]> = {};
  for (const s of snaps ?? []) {
    const key = priceKey(id, s.printing || null);
    (history[key] ??= []).push({ date: s.snapshot_date, price: Number(s.market_price) });
  }
  return NextResponse.json({ product, prices, history }, { headers: { "cache-control": "public, s-maxage=600, stale-while-revalidate=3600" } });
}
