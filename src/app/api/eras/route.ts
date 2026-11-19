import { NextResponse } from "next/server";
import { eraSummaries } from "@/lib/server/era-summary";
import { getAdminSupabase } from "@/lib/supabase/server";

export const maxDuration = 60;

/** GET /api/eras — how the modern, mid-era and vintage markets moved, with their biggest moves. */
export async function GET() {
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ eras: [] });
  try {
    const eras = await eraSummaries(admin);
    return NextResponse.json({ eras }, { headers: { "cache-control": "public, s-maxage=1800, stale-while-revalidate=21600" } });
  } catch (e) {
    console.error("eras", e);
    return NextResponse.json({ eras: [] }, { headers: { "cache-control": "no-store" } });
  }
}
