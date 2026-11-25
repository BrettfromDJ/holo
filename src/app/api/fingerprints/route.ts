import type { SupabaseClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { getAdminSupabase } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

/**
 * The nightly fingerprint job (GitHub "Card fingerprints" workflow, on a Mac) talks to this:
 * GET  /api/fingerprints?limit=500 — cards still to fingerprint (id and picture);
 * POST /api/fingerprints — { prints: [{ productId, imageUrl, print: number[] }] } saved.
 * Both need FINGERPRINTS_SECRET (a long random value), set in Vercel and as the same-named
 * GitHub Actions secret (its own key, so the hidden CRON_SECRET never needs copying).
 */
function authorized(req: Request): boolean {
  const auth = req.headers.get("authorization");
  return [process.env.FINGERPRINTS_SECRET, process.env.CRON_SECRET].some((s) => Boolean(s) && auth === `Bearer ${s}`);
}

function db(): SupabaseClient | null {
  return getAdminSupabase() as unknown as SupabaseClient | null;
}

const OVERSIZED = /(over-?\s?sized?|\bjumbo\b)/i;

/**
 * Walking the catalog in id order from a bookmark (`after`): each call reads the next stretch of
 * products and returns the ones still to fingerprint, plus where to carry on (`next`; null at the
 * end). The single big query (card_prints_todo) timed out once most cards had a fingerprint, as it
 * had to skip past all of them every time; this stays quick however many are done, and steps past
 * pictures that can't be read without asking for them again.
 */
async function todoFrom(admin: SupabaseClient, after: string, limit: number) {
  const { data: sets, error: setsError } = await admin.from("catalog_sets").select("slug").ilike("game_name", "%pok%");
  if (setsError) throw new Error(setsError.message);
  const pokemon = new Set(((sets ?? []) as { slug: string }[]).map((s) => s.slug));
  const cards: { productId: string; imageUrl: string }[] = [];
  let cursor = after;
  let scanned = 0;
  const started = Date.now();
  while (cards.length < limit && scanned < 20000 && Date.now() - started < 40_000) {
    const { data, error } = await admin
      .from("products")
      .select("id, image_url, set_id, name")
      .eq("kind", "single")
      .not("image_url", "is", null)
      .gt("id", cursor)
      .order("id")
      .limit(1000);
    if (error) throw new Error(error.message);
    const rows = (data ?? []) as { id: string; image_url: string; set_id: string | null; name: string }[];
    if (!rows.length) return { cards, next: null as string | null };
    scanned += rows.length;
    cursor = rows[rows.length - 1].id;
    const wanted = rows.filter((r) => r.set_id && pokemon.has(r.set_id) && !OVERSIZED.test(r.name));
    // Which of these already have a fingerprint of the same picture (asked in small groups).
    const done = new Map<string, string>();
    for (let i = 0; i < wanted.length; i += 150) {
      const ids = wanted.slice(i, i + 150).map((r) => r.id);
      const { data: have, error: haveError } = await admin.from("card_prints").select("product_id, image_url").in("product_id", ids);
      if (haveError) throw new Error(haveError.message);
      for (const h of (have ?? []) as { product_id: string; image_url: string }[]) done.set(h.product_id, h.image_url);
    }
    for (const r of wanted) {
      if (done.get(r.id) === r.image_url) continue;
      cards.push({ productId: r.id, imageUrl: r.image_url });
      if (cards.length >= limit) { cursor = r.id; break; }
    }
  }
  return { cards, next: cursor };
}

export async function GET(req: Request) {
  if (!authorized(req)) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const admin = db();
  if (!admin) return NextResponse.json({ error: "no database" }, { status: 503 });
  const params = new URL(req.url).searchParams;
  const limit = Math.min(2000, Math.max(1, Number(params.get("limit")) || 500));
  // The nightly job sends a bookmark (`after`, empty at the start): walk the catalog from it.
  if (params.has("after")) {
    try {
      return NextResponse.json(await todoFrom(admin, params.get("after") ?? "", limit));
    } catch (e) {
      return NextResponse.json({ error: e instanceof Error ? e.message : String(e) }, { status: 500 });
    }
  }
  const { data, error } = await admin.rpc("card_prints_todo", { lim: limit });
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  const cards = ((data ?? []) as { product_id: string; image_url: string }[]).map((r) => ({ productId: r.product_id, imageUrl: r.image_url }));
  return NextResponse.json({ cards });
}

export async function POST(req: Request) {
  if (!authorized(req)) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const admin = db();
  if (!admin) return NextResponse.json({ error: "no database" }, { status: 503 });
  const body = (await req.json().catch(() => null)) as { prints?: { productId: string; imageUrl: string; print: number[] }[] } | null;
  const prints = (body?.prints ?? []).filter((p) => p.productId && p.imageUrl && Array.isArray(p.print) && p.print.length > 0).slice(0, 500);
  if (!prints.length) return NextResponse.json({ saved: 0 });
  const rows = prints.map((p) => ({
    product_id: p.productId,
    image_url: p.imageUrl,
    print: `[${p.print.map((x) => Number(x).toFixed(6)).join(",")}]`,
    revision: 2,
    updated_at: new Date().toISOString(),
  }));
  const { error } = await admin.from("card_prints").upsert(rows);
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ saved: rows.length });
}
