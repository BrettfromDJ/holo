import { NextResponse } from "next/server";
import { EXPLORE_CACHE, setFromRow } from "@/lib/server/explore";
import { getAdminSupabase } from "@/lib/supabase/server";

/** GET /api/explore — every set in the stored catalog, newest first. */
export async function GET() {
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ error: { message: "Explore needs Supabase to be configured." } }, { status: 503 });
  const { data, error } = await admin.from("catalog_sets").select("*").order("release_date", { ascending: false, nullsFirst: false }).limit(3000);
  if (error) {
    const missing = /catalog_sets/.test(error.message);
    return NextResponse.json(
      { error: { message: missing ? "Run supabase/migrations/20261027000000_catalog_sets.sql in Supabase to enable Explore." : error.message } },
      { status: missing ? 503 : 500 },
    );
  }
  const sets = (data ?? []).map(setFromRow);
  // Never cache an empty or barely-started catalog, so the first sync shows up right away.
  const cache = sets.some((s) => s.loaded) ? EXPLORE_CACHE : "no-store";
  return NextResponse.json({ sets }, { headers: { "cache-control": cache } });
}
