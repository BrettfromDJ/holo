import { NextResponse } from "next/server";
import { isTcgApiConfigured } from "@/lib/pricing/tcgapi";
import { syncCatalog } from "@/lib/server/catalog-sync";
import { getAdminSupabase } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
export const maxDuration = 300;

/**
 * Daily Explore catalog sync (Vercel Cron, see vercel.json). Uses at most
 * CATALOG_SYNC_MAX_CALLS requests (default 40) and always leaves
 * CATALOG_SYNC_RESERVE (default 30) of the day's TCG API budget for the app.
 */
export async function GET(req: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret || req.headers.get("authorization") !== `Bearer ${secret}`) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ error: "Supabase service role is not configured." }, { status: 503 });
  if (!isTcgApiConfigured()) return NextResponse.json({ error: "TCG API key is not configured." }, { status: 503 });

  const maxCalls = Number(process.env.CATALOG_SYNC_MAX_CALLS) || 40;
  const reserve = Number(process.env.CATALOG_SYNC_RESERVE) || 30;
  const result = await syncCatalog(admin, { maxCalls, reserve });
  return NextResponse.json(result, { status: result.stoppedBecause === "error" ? 500 : 200 });
}
