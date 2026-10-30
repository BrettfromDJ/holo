import { NextResponse } from "next/server";
import { parseQuery, rankByQuery } from "@/lib/search-query";
import { EXPLORE_CACHE, withPrices } from "@/lib/server/explore";
import { selectAll } from "@/lib/server/paging";
import type { ProductRow } from "@/lib/supabase/database.types";
import { productFromRow } from "@/lib/supabase/mappers";
import { getAdminSupabase } from "@/lib/supabase/server";

/**
 * GET /api/explore/search?q=[&offset=0&limit=80] — search across the stored
 * catalog (no TCG API calls). Every distinguishing word must appear in the name
 * or set; a product type in the query ("etb", "booster box") then ranks matching
 * products first. Every match is ranked, then returned a page at a time with the
 * total, so a whole set ("evolving skies") can be scrolled through.
 */
export async function GET(req: Request) {
  const q = parseQuery((new URL(req.url).searchParams.get("q") ?? "").slice(0, 80));
  const words = (q.core || q.category?.toLowerCase() || "")
    .split(" ")
    .map((w) => w.replace(/[%_,()*]/g, ""))
    .filter((w) => w.length >= 2)
    .slice(0, 6);
  if (!words.length) return NextResponse.json({ products: [], total: 0 });
  const params = new URL(req.url).searchParams;
  const offset = Math.max(0, Number(params.get("offset")) || 0);
  const limit = Math.min(200, Math.max(1, Number(params.get("limit")) || 80));
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ error: { message: "Explore needs Supabase to be configured." } }, { status: 503 });
  let rows: ProductRow[];
  try {
    rows = await selectAll<ProductRow>((from, to) => {
      let query = admin.from("products").select("*").eq("source", "tcgapi");
      for (const w of words) query = query.or(`name.ilike.*${w}*,set_name.ilike.*${w}*`);
      return query.order("id").range(from, to);
    }, 3000);
  } catch (e) {
    return NextResponse.json({ error: { message: (e as Error).message } }, { status: 500 });
  }
  // Rank every match (ranking doesn't need prices), then price just the page asked for.
  const ranked = rankByQuery(rows.map((row) => ({ row, product: productFromRow(row) })), q);
  const page = await withPrices(admin, ranked.slice(offset, offset + limit).map((r) => r.row));
  return NextResponse.json({ products: page, total: ranked.length, offset, hasMore: offset + limit < ranked.length }, { headers: { "cache-control": EXPLORE_CACHE } });
}
