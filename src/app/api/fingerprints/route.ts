import type { SupabaseClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { getAdminSupabase } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

/**
 * The nightly fingerprint job (GitHub "Card fingerprints" workflow, on a Mac) talks to this:
 * GET  /api/fingerprints?limit=500 — cards still to fingerprint (id and picture);
 * POST /api/fingerprints — { prints: [{ productId, imageUrl, print: number[] }] } saved.
 * Both need the CRON_SECRET (the same one Vercel's cron uses), as a GitHub secret.
 */
function authorized(req: Request): boolean {
  const secret = process.env.CRON_SECRET;
  return Boolean(secret) && req.headers.get("authorization") === `Bearer ${secret}`;
}

function db(): SupabaseClient | null {
  return getAdminSupabase() as unknown as SupabaseClient | null;
}

export async function GET(req: Request) {
  if (!authorized(req)) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const admin = db();
  if (!admin) return NextResponse.json({ error: "no database" }, { status: 503 });
  const limit = Math.min(2000, Math.max(1, Number(new URL(req.url).searchParams.get("limit")) || 500));
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
