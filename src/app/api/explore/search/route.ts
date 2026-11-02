import { NextResponse } from "next/server";
import { canFuzz, fuzzyAnchors, fuzzyFilter, matchesNumber, numberPatterns, splitNumber, type NumberQuery } from "@/lib/search-match";
import { parseQuery, rankByQuery, scoreProduct } from "@/lib/search-query";
import { EXPLORE_CACHE, withPrices } from "@/lib/server/explore";
import { selectAll } from "@/lib/server/paging";
import type { ProductRow } from "@/lib/supabase/database.types";
import { productFromRow } from "@/lib/supabase/mappers";
import { getAdminSupabase } from "@/lib/supabase/server";

/**
 * GET /api/explore/search?q=[&offset=0&limit=80] — search across the stored
 * catalog (no TCG API calls). Every distinguishing word must appear in the name
 * or set; a product type in the query ("etb", "booster box") then ranks matching
 * products first. A collector number ("215/203", "#215", "TG05") matches the
 * `number` column, alone or with name words ("umbreon 215"). When nothing
 * matches, a typo-tolerant pass looks for close matches ("charzard") and the
 * reply says `fuzzy: true`. Every match is ranked, then returned a page at a time
 * with the total, so a whole set ("evolving skies") can be scrolled through.
 */
export async function GET(req: Request) {
  const params = new URL(req.url).searchParams;
  const q = parseQuery((params.get("q") ?? "").slice(0, 80));
  const all = (q.core || q.category?.toLowerCase() || "")
    .split(" ")
    .map((w) => w.replace(/[%_,()*]/g, ""))
    .filter(Boolean)
    .slice(0, 6);
  const { words: rest, number } = splitNumber(all);
  const words = rest.filter((w) => w.length >= 2);
  if (!words.length && !number) return NextResponse.json({ products: [], total: 0 });
  const offset = Math.max(0, Number(params.get("offset")) || 0);
  const limit = Math.min(200, Math.max(1, Number(params.get("limit")) || 80));
  const admin = getAdminSupabase();
  if (!admin) return NextResponse.json({ error: { message: "Explore needs Supabase to be configured." } }, { status: 503 });

  // The number's own condition: its column, or (for a bare "151") the name or set too.
  const numberClause = number
    ? [...numberPatterns(number).map((p) => `number.ilike.${p}`), ...(number.explicit ? [] : [`name.ilike.*${numberWordOf(number)}*`, `set_name.ilike.*${numberWordOf(number)}*`])].join(",")
    : null;
  // A number on its own matches widely ("25"), so fewer rows are read.
  const cap = words.length ? 3000 : 1000;

  let rows: ProductRow[];
  let fuzzy = false;
  try {
    rows = await selectAll<ProductRow>((from, to) => {
      let query = admin.from("products").select("*").eq("source", "tcgapi");
      for (const w of words) query = query.or(`name.ilike.*${w}*,set_name.ilike.*${w}*`);
      if (numberClause) query = query.or(numberClause);
      return query.order("id").range(from, to);
    }, cap);
    if (number?.explicit) rows = rows.filter((r) => matchesNumber(r.number, number));

    // Nothing at all: try close spellings ("charzard", "umbreon vmx").
    if (!rows.length && canFuzz(words)) {
      const candidates = await selectAll<ProductRow>((from, to) => {
        let query = admin.from("products").select("*").eq("source", "tcgapi");
        for (const w of words) query = query.or(fuzzyAnchors(w).flatMap((a) => [`name.ilike.*${a}*`, `set_name.ilike.*${a}*`]).join(","));
        if (numberClause) query = query.or(numberClause);
        return query.order("id").range(from, to);
      }, 1500);
      const close = fuzzyFilter(
        candidates.filter((r) => !number?.explicit || matchesNumber(r.number, number)),
        words,
        (r) => `${r.name} ${r.set_name ?? ""}`,
      );
      if (close.length) {
        rows = close;
        fuzzy = true;
      }
    }
  } catch (e) {
    return NextResponse.json({ error: { message: (e as Error).message } }, { status: 500 });
  }

  // Rank every match (ranking doesn't need prices), then price just the page asked for.
  // Fuzzy matches arrive closest first; the usual ranking keeps that order for ties.
  const items = rows.map((row) => ({ row, product: productFromRow(row) }));
  const ranked = number ? await rankWithNumber(admin, items, q, number, words.length === 0) : rankByQuery(items, q);
  const page = await withPrices(admin, ranked.slice(offset, offset + limit).map((r) => r.row));
  return NextResponse.json(
    { products: page, total: ranked.length, offset, hasMore: offset + limit < ranked.length, ...(fuzzy ? { fuzzy: true } : {}) },
    { headers: { "cache-control": EXPLORE_CACHE } },
  );
}

/** The number as typed without "#" or a total, for matching it as a word ("151"). */
function numberWordOf(n: NumberQuery): string {
  return `${n.prefix}${n.digits}`;
}

type Item = { row: ProductRow; product: ReturnType<typeof productFromRow> };

/**
 * With a collector number: the exact number first (strongly when it's the whole query), then
 * the usual relevance, then the newest set first.
 */
async function rankWithNumber(admin: NonNullable<ReturnType<typeof getAdminSupabase>>, items: Item[], q: ReturnType<typeof parseQuery>, n: NumberQuery, alone: boolean): Promise<Item[]> {
  const released = new Map<string, string>();
  const setIds = [...new Set(items.map((i) => i.row.set_id).filter((x): x is string => Boolean(x)))];
  for (let i = 0; i < setIds.length; i += 300) {
    const { data } = await admin.from("catalog_sets").select("slug, release_date").in("slug", setIds.slice(i, i + 300));
    for (const s of data ?? []) if (s.release_date) released.set(s.slug, s.release_date);
  }
  const bonus = alone ? 1 : 0.5;
  return items
    .map((item, i) => ({
      item,
      i,
      s: scoreProduct(item.product, q) + (matchesNumber(item.row.number, n) ? bonus : 0),
      d: (item.row.set_id && released.get(item.row.set_id)) || "",
    }))
    .sort((a, b) => b.s - a.s || (a.d === b.d ? 0 : a.d < b.d ? 1 : -1) || a.i - b.i)
    .map((x) => x.item);
}
