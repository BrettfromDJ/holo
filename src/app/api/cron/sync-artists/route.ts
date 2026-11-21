import { NextResponse } from "next/server";
import { syncArtists } from "@/lib/server/artists";
import { getAdminSupabase } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
export const maxDuration = 300;

/** Fills card artists for sets not done yet (free source; started by the nightly catalog job). */
export async function GET(req: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret || req.headers.get("authorization") !== `Bearer ${secret}`) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ error: "Supabase service role is not configured." }, { status: 503 });
  try {
    return NextResponse.json(await syncArtists(admin));
  } catch (e) {
    return NextResponse.json({ error: String(e) }, { status: 500 });
  }
}
