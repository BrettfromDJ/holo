import { after, NextResponse } from "next/server";
import { refreshSetIfStale } from "@/lib/server/catalog-sync";
import { selectAll } from "@/lib/server/paging";
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
  // This card's prices are more than a day old: refresh its whole set after answering.
  const { data: price } = await admin.from("product_prices").select("fetched_at").eq("product_id", id).order("fetched_at", { ascending: false }).limit(1).maybeSingle();
  if (row.set_id && (!price || Date.now() - Date.parse(price.fetched_at) > 20 * 60 * 60 * 1000)) {
    const setId = row.set_id;
    after(async () => {
      const { data: set } = await admin.from("catalog_sets").select("slug, tcgapi_id, name, products_synced_at").eq("slug", setId).maybeSingle();
      if (set) await refreshSetIfStale(admin, set).catch(() => {});
    });
  }

  const [{ data: priceRows }, { data: snaps }] = await Promise.all([
    admin.from("product_prices").select("*").eq("product_id", id),
    selectAll<{ printing: string; snapshot_date: string; market_price: number }>((from, to) =>
      admin.from("price_snapshots").select("printing, snapshot_date, market_price").eq("product_id", id).order("snapshot_date").order("printing").range(from, to),
    ).then((data) => ({ data })),
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
