import { NextResponse } from "next/server";
import { themes } from "@/lib/server/themes";
import { getAdminSupabase } from "@/lib/supabase/server";

export const maxDuration = 60;

/**
 * GET /api/themes — Home's themed collections ("Skyridge holos", "Charizard through the
 * years"…) with their cards, from our own catalog (no TCG API). The same for everyone; the app
 * picks a few each time it opens.
 */
export async function GET() {
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ themes: [] });
  const list = await themes(admin);
  return NextResponse.json(
    { themes: list },
    { headers: { "cache-control": list.length >= 10 ? "public, s-maxage=3600, stale-while-revalidate=86400" : "no-store" } },
  );
}
