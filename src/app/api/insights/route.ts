import { NextResponse } from "next/server";
import { marketInsights } from "@/lib/server/insights";
import { getAdminSupabase } from "@/lib/supabase/server";

/**
 * GET /api/insights — Home's daily insights ("Today in the hobby" and a line on why each
 * highlighted card moved), written by Claude once a day and saved. Empty without
 * ANTHROPIC_API_KEY.
 */
export async function GET() {
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ day: null, briefing: null, reasons: {} });
  const insights = await marketInsights(admin);
  // The same for everyone all day: kept at the edge for an hour.
  return NextResponse.json(insights, {
    headers: { "cache-control": insights.briefing ? "public, s-maxage=3600, stale-while-revalidate=86400" : "no-store" },
  });
}
