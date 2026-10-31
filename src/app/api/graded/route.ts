import { NextResponse } from "next/server";
import { getAdminSupabase } from "@/lib/supabase/server";

/** What we return per product: ungraded and each grade's value, in dollars. */
export interface GradedValues {
  ungraded: number | null;
  grades: Record<string, number>;
  updatedAt: string;
}

const LABELS: [string, string][] = [
  ["psa_10", "PSA 10"],
  ["bgs_10", "BGS 10"],
  ["cgc_10", "CGC 10"],
  ["sgc_10", "SGC 10"],
  ["grade_9_5", "9.5"],
  ["grade_9", "9"],
  ["grade_8", "8"],
  ["grade_7", "7"],
];

/**
 * GET /api/graded?ids=tcgapi:1,tcgapi:2 — PriceCharting's graded values for catalog products,
 * matched by TCGplayer id. Read from storage (downloaded nightly), so it costs no API calls.
 * Grades below 10 are for any grader ("9.5"); 10s are per grader ("PSA 10").
 */
export async function GET(req: Request) {
  const ids = (new URL(req.url).searchParams.get("ids") ?? "").split(",").filter((id) => /^tcgapi:\d+$/.test(id)).slice(0, 500);
  const admin = getAdminSupabase();
  if (!ids.length || !admin) return NextResponse.json({ graded: {} });
  const { data: products } = await admin.from("products").select("id, tcgplayer_id").in("id", ids);
  const byTcg = new Map<number, string>();
  for (const p of products ?? []) if (p.tcgplayer_id) byTcg.set(p.tcgplayer_id, p.id);
  if (!byTcg.size) return NextResponse.json({ graded: {} });
  const { data: rows } = await admin.from("pricecharting_prices").select("*").in("tcg_id", [...byTcg.keys()]);
  // Variants can share a TCGplayer id; keep the one that sells most.
  const best = new Map<number, NonNullable<typeof rows>[number]>();
  for (const r of rows ?? []) {
    if (r.tcg_id === null) continue;
    const prev = best.get(r.tcg_id);
    if (!prev || (r.sales_volume ?? 0) > (prev.sales_volume ?? 0)) best.set(r.tcg_id, r);
  }
  const graded: Record<string, GradedValues> = {};
  for (const [tcg, r] of best) {
    const id = byTcg.get(tcg)!;
    const grades: Record<string, number> = {};
    for (const [col, label] of LABELS) {
      const v = r[col as keyof typeof r];
      if (typeof v === "number" || (typeof v === "string" && v)) grades[label] = Number(v);
    }
    graded[id] = { ungraded: r.ungraded === null ? null : Number(r.ungraded), grades, updatedAt: r.updated_at };
  }
  return NextResponse.json({ graded }, { headers: { "cache-control": "public, s-maxage=3600, stale-while-revalidate=86400" } });
}
