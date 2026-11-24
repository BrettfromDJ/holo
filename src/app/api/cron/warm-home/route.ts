import { NextResponse } from "next/server";
import { themes } from "@/lib/server/themes";
import { getAdminSupabase } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
export const maxDuration = 300;

/**
 * Builds Home's themed collections ahead of time (started by the nightly catalog job), so
 * nobody waits while ~70 are worked out on the day's first open: today's (if any are missing)
 * and tomorrow's (they're saved per UTC day, and the day turns over in the evening in the US).
 * Then asks for the market and the insights once, so those are saved too.
 */
export async function GET(req: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret || req.headers.get("authorization") !== `Bearer ${secret}`) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ error: "Supabase service role is not configured." }, { status: 503 });
  const today = new Date().toISOString().slice(0, 10);
  const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
  const built: Record<string, number> = {};
  try {
    built[today] = (await themes(admin, { day: today, budgetMs: 110_000 })).length;
    built[tomorrow] = (await themes(admin, { day: tomorrow, budgetMs: 110_000 })).length;
  } catch (e) {
    return NextResponse.json({ error: String(e), built }, { status: 500 });
  }
  // The market and the day's insights, so the first open reads saved copies.
  const url = new URL(req.url);
  for (const path of ["/api/explore", "/api/insights"]) {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 30_000);
    await fetch(new URL(path, url), { signal: ctrl.signal }).catch(() => {});
    clearTimeout(timer);
  }
  return NextResponse.json({ built });
}
