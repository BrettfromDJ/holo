import { after, NextResponse } from "next/server";
import { refreshSetIfStale } from "@/lib/server/catalog-sync";
import { editionPreference, EXPLORE_CACHE, setFromRow, withPrices } from "@/lib/server/explore";
import { parseEditionSlug } from "@/lib/editions";
import { selectAll } from "@/lib/server/paging";
import type { ProductRow } from "@/lib/supabase/database.types";
import { getAdminSupabase } from "@/lib/supabase/server";

/** GET /api/explore/sets/<slug> — a set and all of its stored products with prices (`?meta=1`: the set only). */
export async function GET(req: Request, { params }: { params: Promise<{ slug: string }> }) {
  const { slug: asked } = await params;
  // One edition of an old set ("base-set--1st-edition"): the catalog set, priced at that edition.
  const half = parseEditionSlug(asked);
  const slug = half?.slug ?? asked;
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ error: { message: "Explore needs Supabase to be configured." } }, { status: 503 });
  let { data: set } = await admin.from("catalog_sets").select("*").eq("slug", slug).maybeSingle();
  if (!set) return NextResponse.json({ error: { message: "Set not found." } }, { status: 404 });
  if (!set.products_synced_at) {
    // Never loaded: load it now (a call or two per 200 products), so whoever opened it sees its
    // cards instead of "on the way". Then read the set again for its new count.
    await refreshSetIfStale(admin, set).catch(() => {});
    set = (await admin.from("catalog_sets").select("*").eq("slug", slug).maybeSingle()).data ?? set;
  } else {
    // Prices more than a day old: refresh this set after answering, so the next look is current.
    after(() => refreshSetIfStale(admin, set!).catch(() => {}));
  }
  // A set that still has nothing isn't cached, so the next look tries again.
  const cache = set.products_synced_at ? EXPLORE_CACHE : "no-store";
  if (new URL(req.url).searchParams.get("meta")) return NextResponse.json({ set: setFromRow(set, new URL(req.url).origin, half?.edition) }, { headers: { "cache-control": cache } });
  let rows: ProductRow[];
  try {
    rows = await selectAll<ProductRow>((from, to) => admin.from("products").select("*").eq("set_id", slug).order("id").range(from, to), 10_000);
  } catch (e) {
    return NextResponse.json({ error: { message: (e as Error).message } }, { status: 500 });
  }
  return NextResponse.json({ set: setFromRow(set, new URL(req.url).origin, half?.edition), products: await withPrices(admin, rows, half ? editionPreference(half.edition) : undefined) }, { headers: { "cache-control": rows.length ? cache : "no-store" } });
}
