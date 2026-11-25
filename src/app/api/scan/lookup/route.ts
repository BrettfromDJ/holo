import { NextResponse } from "next/server";
import { matchesNumber, numberPatterns, parseNumberToken } from "@/lib/search-match";
import { withPrices } from "@/lib/server/explore";
import { allowRequest, clientKey } from "@/lib/server/rate-limit";
import type { ProductRow } from "@/lib/supabase/database.types";
import { getAdminSupabase } from "@/lib/supabase/server";

/**
 * POST /api/scan/lookup — { number?: "074/131", name?: "Eevee" } → { products } (the same shape as
 * /api/explore/search). The phone scanner's one quick question after reading a card: every single
 * with that card number whose set total is the one read or one off (a "131" read as "130"), and,
 * when a name was read, singles whose name starts with it. One request in place of three general
 * searches (each took seconds: ranking, fuzzy passes and paging the scanner doesn't need).
 */
export async function POST(req: Request) {
  if (!allowRequest(clientKey(req, "scan-lookup"), 60, 60)) return NextResponse.json({ error: { message: "Too many scans at once." } }, { status: 429 });
  const body = (await req.json().catch(() => null)) as { number?: string; name?: string } | null;
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ products: [] });
  const number = typeof body?.number === "string" ? parseNumberToken(body.number.slice(0, 20)) : null;
  const name = typeof body?.name === "string" ? body.name.replace(/[%_,()*]/g, "").trim().slice(0, 40) : "";

  const [byNumber, byName] = await Promise.all([
    number
      ? admin.from("products").select("*").eq("source", "tcgapi").eq("kind", "single")
          .or(numberPatterns({ ...number, total: null }).map((p) => `number.ilike.${p}`).join(","))
          .limit(400)
      : Promise.resolve({ data: [] as ProductRow[] }),
    name.length >= 3
      ? admin.from("products").select("*").eq("source", "tcgapi").eq("kind", "single").ilike("name", `${name}%`).limit(60)
      : Promise.resolve({ data: [] as ProductRow[] }),
  ]);

  // The number's own card, or its total one off; nothing else with that number.
  const total = number?.total ? Number(number.total.digits) : null;
  const numbered = ((byNumber.data ?? []) as ProductRow[]).filter((r) => {
    if (!number) return false;
    // A total was read: the card must print one too (a bare "074" isn't this card).
    if (number.total && !(r.number ?? "").includes("/")) return false;
    if (matchesNumber(r.number, number)) return true;
    const t = Number((r.number ?? "").split("/")[1]?.replace(/\D/g, ""));
    return total !== null && Number.isFinite(t) && Math.abs(t - total) === 1 && matchesNumber(r.number, { ...number, total: null });
  });
  const seen = new Set<string>();
  const rows = [...numbered, ...((byName.data ?? []) as ProductRow[])].filter((r) => !seen.has(r.id) && seen.add(r.id));
  return NextResponse.json({ products: await withPrices(admin, rows.slice(0, 120)) });
}
