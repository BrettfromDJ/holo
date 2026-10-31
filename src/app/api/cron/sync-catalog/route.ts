import { after, NextResponse } from "next/server";
import { dailyBudget, isTcgApiConfigured } from "@/lib/pricing/tcgapi";
import { syncCatalog } from "@/lib/server/catalog-sync";
import { getAdminSupabase } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
export const maxDuration = 300;

/** At most this many runs chain off one cron call (a backstop; the daily budget stops it first). */
const MAX_HOPS = 60;

/**
 * Explore catalog sync (Vercel Cron, see vercel.json): keeps every set's prices no more than
 * a day old. One run makes at most CATALOG_SYNC_MAX_CALLS TCG API requests (default 400) and
 * stops near Vercel's time limit; while sets are still due it starts the next run itself, until
 * today's requests reach CATALOG_SYNC_DAILY_CALLS (default 7,000 of the plan's 10,000, leaving
 * the rest for prices of owned cards, history, eBay and live searches) or a 429.
 */
export async function GET(req: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret || req.headers.get("authorization") !== `Bearer ${secret}`) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ error: "Supabase service role is not configured." }, { status: 503 });
  if (!isTcgApiConfigured()) return NextResponse.json({ error: "TCG API key is not configured." }, { status: 503 });

  const maxCalls = Number(process.env.CATALOG_SYNC_MAX_CALLS) || 400;
  const dailyCalls = Number(process.env.CATALOG_SYNC_DAILY_CALLS) || 7000;
  const url = new URL(req.url);
  const hop = Number(url.searchParams.get("hop")) || 0;
  // Once a night: start PriceCharting's download (its own request and time limit), then clear
  // expired shared answers and old per-person counters.
  if (hop === 0 && process.env.PRICECHARTING_TOKEN) {
    const pc = new URL("/api/cron/sync-pricecharting", url);
    after(async () => {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), 8000);
      await fetch(pc, { headers: { authorization: `Bearer ${secret}` }, signal: ctrl.signal }).catch(() => {});
      clearTimeout(timer);
    });
  }
  if (hop === 0) {
    const now = new Date();
    await admin.from("api_cache").delete().lt("expires_at", now.toISOString()).then(() => undefined, () => undefined);
    const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
    await admin.from("api_quota").delete().lt("day", weekAgo).then(() => undefined, () => undefined);
  }
  const result = await syncCatalog(admin, { maxCalls, dailyCalls });

  // More sets are due and there's budget left: start the next run once this one has answered.
  // The next run is its own request with its own time limit; this one only waits to send it.
  const more = (result.stoppedBecause === "budget" || result.stoppedBecause === "time") && hop < MAX_HOPS;
  if (more) {
    url.searchParams.set("hop", String(hop + 1));
    after(async () => {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), 8000);
      await fetch(url, { headers: { authorization: `Bearer ${secret}` }, signal: ctrl.signal }).catch(() => {});
      clearTimeout(timer);
    });
  }
  return NextResponse.json(
    { ...result, hop, continuing: more, apiBudget: dailyBudget(), maxCalls, dailyCalls },
    { status: result.stoppedBecause === "error" ? 500 : 200 },
  );
}
