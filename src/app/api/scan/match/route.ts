import type { SupabaseClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { withPrices } from "@/lib/server/explore";
import { allowRequest, clientKey } from "@/lib/server/rate-limit";
import type { Database, ProductRow } from "@/lib/supabase/database.types";
import { getAdminSupabase } from "@/lib/supabase/server";

/**
 * POST /api/scan/match — { print: number[] } (a scan's Vision fingerprint, made on the phone)
 * → the closest cards in the whole catalog, nearest first, each with its distance. With
 * { print, ids } → { distances: [{ productId, imageUrl, distance }] } for just those cards. Free: no paid
 * scan; the phone decides whether the nearest is clearly the one.
 */
export async function POST(req: Request) {
  if (!allowRequest(clientKey(req, "match"), 30, 60)) return NextResponse.json({ error: { message: "Too many scans at once." } }, { status: 429 });
  const body = (await req.json().catch(() => null)) as { print?: number[]; k?: number; ids?: string[] } | null;
  const print = body?.print;
  if (!Array.isArray(print) || print.length < 16 || print.length > 4096) return NextResponse.json({ error: { message: "Send a fingerprint." } }, { status: 400 });
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ matches: [] });
  const loose = admin as unknown as SupabaseClient;
  // Among a few cards the phone already narrowed it to (by the text it read): their stored
  // fingerprints against the scan's, worked out here, so the phone needn't download and
  // fingerprint each card's picture (that took seconds a scan).
  if (Array.isArray(body?.ids)) {
    const ids = body.ids.filter((x): x is string => typeof x === "string").slice(0, 40);
    if (!ids.length) return NextResponse.json({ distances: [] });
    const { data: rows, error: listError } = await loose.from("card_prints").select("product_id, image_url, print").in("product_id", ids);
    if (listError) return NextResponse.json({ error: { message: listError.message } }, { status: 500 });
    const distances = ((rows ?? []) as { product_id: string; image_url: string; print: string | number[] }[]).flatMap((r) => {
      const theirs = typeof r.print === "string" ? (JSON.parse(r.print) as number[]) : r.print;
      if (!Array.isArray(theirs) || theirs.length !== print.length) return [];
      let sum = 0;
      for (let i = 0; i < theirs.length; i++) { const d = theirs[i] - Number(print[i]); sum += d * d; }
      return [{ productId: r.product_id, imageUrl: r.image_url, distance: Math.sqrt(sum) }];
    });
    distances.sort((a, b) => a.distance - b.distance);
    return NextResponse.json({ distances });
  }
  const k = Math.min(10, Math.max(1, Number(body?.k) || 5));
  const { data, error } = await loose.rpc("match_card_prints", { query: `[${print.map((x) => Number(x).toFixed(6)).join(",")}]`, k });
  if (error) return NextResponse.json({ error: { message: error.message } }, { status: 500 });
  const near = (data ?? []) as { product_id: string; distance: number }[];
  if (!near.length) return NextResponse.json({ matches: [] });
  const { data: rows } = await (admin as SupabaseClient<Database>).from("products").select("*").in("id", near.map((n) => n.product_id));
  const priced = await withPrices(admin, (rows ?? []) as ProductRow[]);
  const byId = new Map(priced.map((p) => [p.product.id, p]));
  const matches = near.flatMap((n) => {
    const hit = byId.get(n.product_id);
    return hit ? [{ ...hit, distance: n.distance }] : [];
  });
  return NextResponse.json({ matches });
}
