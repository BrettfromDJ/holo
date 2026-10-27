import { NextResponse } from "next/server";
import { addDays } from "@/lib/finance/dates";
import { providerFor } from "@/lib/pricing";
import { errorResponse } from "@/lib/server/http";
import { selectAll } from "@/lib/server/paging";
import { allowRequest, clientKey } from "@/lib/server/rate-limit";
import { getAdminSupabase, getServerSupabase } from "@/lib/supabase/server";

/** History reaching back this far counts as already loaded. */
const ENOUGH_DAYS = 60;
const DAY = 24 * 60 * 60 * 1000;
/** Products fetched recently on this server; a refetch within a day is skipped. */
const recentlyFetched = new Map<string, number>();

/**
 * POST /api/explore/products/<id>/history { printing } — full price history.
 * Served from storage when it already reaches back far enough (or was fetched
 * in the last day); otherwise, for signed-in users, fetched from TCG API with
 * one request and saved permanently, so later views are free for everyone.
 */
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  if (!allowRequest(clientKey(req, "history"), 10, 10)) {
    return NextResponse.json({ error: { code: "rate_limited", message: "Too many requests — try again in a minute." } }, { status: 429 });
  }
  const id = decodeURIComponent((await params).id);
  const body = await req.json().catch(() => null);
  const printing: string | null = typeof body?.printing === "string" && body.printing ? body.printing : null;
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ error: { message: "Supabase isn't configured." } }, { status: 503 });

  const stored = async () =>
    (
      await selectAll<{ snapshot_date: string; market_price: number }>((from, to) =>
        admin.from("price_snapshots").select("snapshot_date, market_price").eq("product_id", id).eq("printing", printing ?? "").order("snapshot_date").range(from, to),
      )
    ).map((s) => ({ date: s.snapshot_date, price: Number(s.market_price) }));

  try {
    const existing = await stored();
    const today = new Date().toISOString().slice(0, 10);
    const reachesBack = existing.length > 0 && existing[0].date <= addDays(today, -ENOUGH_DAYS);
    const fetchKey = `${id}|${printing ?? ""}`;
    const fetchedRecently = Date.now() - (recentlyFetched.get(fetchKey) ?? 0) < DAY;
    if (reachesBack || fetchedRecently) return NextResponse.json({ points: existing, available: true, fetched: false });

    // Spending a TCG API request needs an account, so anonymous traffic can't drain the budget.
    const userClient = await getServerSupabase();
    const user = userClient ? (await userClient.auth.getUser()).data.user : null;
    if (!user) return NextResponse.json({ points: existing, available: false, reason: "Sign in to load the full price history.", fetched: false });

    const { data: product } = await admin.from("products").select("id").eq("id", id).maybeSingle();
    if (!product) return NextResponse.json({ error: { message: "Not in the catalog." } }, { status: 404 });

    const { provider, externalId } = providerFor(id);
    recentlyFetched.set(fetchKey, Date.now());
    const h = await provider.getHistory(externalId, printing, "all");
    if (h.points.length) {
      const { error } = await admin.from("price_snapshots").upsert(
        h.points.map((p) => ({ product_id: id, printing: printing ?? "", snapshot_date: p.date, market_price: p.price, source: provider.source })),
        { ignoreDuplicates: true },
      );
      if (error) throw new Error(error.message);
    }
    return NextResponse.json({ points: await stored(), available: h.available, reason: h.reason ?? null, fetched: true });
  } catch (err) {
    return errorResponse(err);
  }
}
