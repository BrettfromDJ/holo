import type { SupabaseClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { withPrices } from "@/lib/server/explore";
import { allowRequest, clientKey } from "@/lib/server/rate-limit";
import type { Database, ProductRow } from "@/lib/supabase/database.types";
import { getAdminSupabase } from "@/lib/supabase/server";

/**
 * POST /api/scan/match — { print: number[] } (a scan's Vision fingerprint, made on the phone)
 * → the closest cards in the whole catalog, nearest first, each with its distance. Free: no paid
 * scan; the phone decides whether the nearest is clearly the one.
 */
export async function POST(req: Request) {
  if (!allowRequest(clientKey(req, "match"), 30, 60)) return NextResponse.json({ error: { message: "Too many scans at once." } }, { status: 429 });
  const body = (await req.json().catch(() => null)) as { print?: number[]; k?: number } | null;
  const print = body?.print;
  if (!Array.isArray(print) || print.length < 16 || print.length > 4096) return NextResponse.json({ error: { message: "Send a fingerprint." } }, { status: 400 });
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ matches: [] });
  const k = Math.min(10, Math.max(1, Number(body?.k) || 5));
  const loose = admin as unknown as SupabaseClient;
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
