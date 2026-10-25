import { NextResponse } from "next/server";
import { dailyBudget, isTcgApiConfigured } from "@/lib/pricing/tcgapi";
import { syncCatalog } from "@/lib/server/catalog-sync";
import { getAdminSupabase } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
export const maxDuration = 300;

/**
 * Daily Explore catalog sync (Vercel Cron, see vercel.json). Makes at most
 * CATALOG_SYNC_MAX_CALLS TCG API requests per run (default 150) and stops early
 * if TCG API refuses a request for being over the daily limit.
 */
export async function GET(req: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret || req.headers.get("authorization") !== `Bearer ${secret}`) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ error: "Supabase service role is not configured." }, { status: 503 });
  if (!isTcgApiConfigured()) return NextResponse.json({ error: "TCG API key is not configured." }, { status: 503 });

  const maxCalls = Number(process.env.CATALOG_SYNC_MAX_CALLS) || 150;
  const result = await syncCatalog(admin, { maxCalls });
  return NextResponse.json({ ...result, apiBudget: dailyBudget(), maxCalls }, { status: result.stoppedBecause === "error" ? 500 : 200 });
}
