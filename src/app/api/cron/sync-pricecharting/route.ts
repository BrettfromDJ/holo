import { NextResponse } from "next/server";
import { fillMissingPrices, isPriceChartingConfigured, syncPriceCharting } from "@/lib/server/pricecharting";
import { getAdminSupabase } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
export const maxDuration = 300;

/**
 * Downloads PriceCharting's price guide for each brand (one request each) and stores the
 * graded and ungraded values. Started by the nightly catalog job; needs PRICECHARTING_TOKEN.
 */
export async function GET(req: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret || req.headers.get("authorization") !== `Bearer ${secret}`) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ error: "Supabase service role is not configured." }, { status: 503 });
  if (!isPriceChartingConfigured()) return NextResponse.json({ error: "PRICECHARTING_TOKEN is not set." }, { status: 503 });
  const results = await syncPriceCharting(admin);
  // Then give cards with no TCGplayer price PriceCharting's ungraded price.
  const filled = await fillMissingPrices(admin).catch(() => 0);
  return NextResponse.json({ results, filled }, { status: results.every((r) => r.error) ? 500 : 200 });
}
