import { NextResponse } from "next/server";
import { EXPLORE_CACHE, setFromRow, withPrices } from "@/lib/server/explore";
import { getAdminSupabase } from "@/lib/supabase/server";

/** GET /api/explore/sets/<slug> — a set and all of its stored products with prices (`?meta=1`: the set only). */
export async function GET(req: Request, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ error: { message: "Explore needs Supabase to be configured." } }, { status: 503 });
  const { data: set } = await admin.from("catalog_sets").select("*").eq("slug", slug).maybeSingle();
  if (!set) return NextResponse.json({ error: { message: "Set not found." } }, { status: 404 });
  if (new URL(req.url).searchParams.get("meta")) return NextResponse.json({ set: setFromRow(set) }, { headers: { "cache-control": EXPLORE_CACHE } });
  const { data: rows, error } = await admin.from("products").select("*").eq("set_id", slug).limit(3000);
  if (error) return NextResponse.json({ error: { message: error.message } }, { status: 500 });
  return NextResponse.json({ set: setFromRow(set), products: await withPrices(admin, rows ?? []) }, { headers: { "cache-control": EXPLORE_CACHE } });
}
