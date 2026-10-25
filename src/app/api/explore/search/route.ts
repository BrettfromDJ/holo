import { NextResponse } from "next/server";
import { parseQuery, rankByQuery } from "@/lib/search-query";
import { EXPLORE_CACHE, withPrices } from "@/lib/server/explore";
import { getAdminSupabase } from "@/lib/supabase/server";

/**
 * GET /api/explore/search?q= — search across the stored catalog (no TCG API
 * calls). Every distinguishing word must appear in the name or set; a product
 * type in the query ("etb", "booster box") then ranks matching products first.
 */
export async function GET(req: Request) {
  const q = parseQuery((new URL(req.url).searchParams.get("q") ?? "").slice(0, 80));
  const words = (q.core || q.category?.toLowerCase() || "")
    .split(" ")
    .map((w) => w.replace(/[%_,()*]/g, ""))
    .filter((w) => w.length >= 2)
    .slice(0, 6);
  if (!words.length) return NextResponse.json({ products: [] });
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ error: { message: "Explore needs Supabase to be configured." } }, { status: 503 });
  let query = admin.from("products").select("*").eq("source", "tcgapi");
  for (const w of words) query = query.or(`name.ilike.*${w}*,set_name.ilike.*${w}*`);
  const { data, error } = await query.limit(200);
  if (error) return NextResponse.json({ error: { message: error.message } }, { status: 500 });
  const ranked = rankByQuery(await withPrices(admin, data ?? []), q).slice(0, 80);
  return NextResponse.json({ products: ranked }, { headers: { "cache-control": EXPLORE_CACHE } });
}
