import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, PriceChartingRow } from "../supabase/database.types";
import { selectAll } from "./paging";

/** The price guide files we read, one per brand (PriceCharting's category names). */
export const PRICECHARTING_CATEGORIES = ["pokemon-cards", "magic-cards", "yugioh-cards", "one-piece-cards"] as const;

/**
 * PriceCharting's columns for trading cards (per its API docs): loose = ungraded, cib =
 * Grade 7, new = Grade 8, graded = Grade 9, box-only = Grade 9.5 (any grader), manual-only =
 * PSA 10, bgs-10 = BGS 10, condition-17 = CGC 10, condition-18 = SGC 10.
 */
const COLUMNS: Record<string, keyof PriceChartingRow> = {
  "loose-price": "ungraded",
  "cib-price": "grade_7",
  "new-price": "grade_8",
  "graded-price": "grade_9",
  "box-only-price": "grade_9_5",
  "manual-only-price": "psa_10",
  "bgs-10-price": "bgs_10",
  "condition-17-price": "cgc_10",
  "condition-18-price": "sgc_10",
};

export function isPriceChartingConfigured(): boolean {
  return Boolean(process.env.PRICECHARTING_TOKEN);
}

/** A CSV file into rows (quoted fields, commas and newlines inside quotes, doubled quotes). */
export function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i++;
        } else quoted = false;
      } else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") {
      row.push(field);
      field = "";
    } else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
    } else field += c;
  }
  if (field || row.length) {
    row.push(field);
    rows.push(row);
  }
  return rows;
}

/** "$1,234.56" (the CSV) or "1234.56" into dollars; blank or zero means no price. */
export function money(v: string | undefined): number | null {
  if (!v) return null;
  const n = Number(v.replace(/[$,\s]/g, ""));
  return Number.isFinite(n) && n > 0 ? n : null;
}

/** One brand's price guide, as rows to store. Only cards with a TCGplayer id can be matched. */
export function guideRows(csv: string): PriceChartingRow[] {
  const [header, ...lines] = parseCsv(csv);
  if (!header) return [];
  const at = (name: string) => header.indexOf(name);
  const id = at("id");
  const tcg = at("tcg-id");
  const out: PriceChartingRow[] = [];
  const now = new Date().toISOString();
  for (const cells of lines) {
    const pcId = Number(cells[id]);
    const tcgId = Number(cells[tcg]);
    // Ids are whole numbers; anything else is a malformed row.
    if (!Number.isInteger(pcId) || !pcId || !Number.isInteger(tcgId) || !tcgId) continue;
    const row: PriceChartingRow = {
      pc_id: pcId,
      tcg_id: tcgId,
      console_name: cells[at("console-name")] || null,
      product_name: cells[at("product-name")] || null,
      ungraded: null,
      grade_7: null,
      grade_8: null,
      grade_9: null,
      grade_9_5: null,
      psa_10: null,
      bgs_10: null,
      cgc_10: null,
      sgc_10: null,
      // Some files (Yu-Gi-Oh) give a decimal sales volume; it's a count, so round it.
      sales_volume: Math.round(Number(cells[at("sales-volume")])) || null,
      updated_at: now,
    };
    for (const [column, key] of Object.entries(COLUMNS)) (row[key] as number | null) = money(cells[at(column)]);
    out.push(row);
  }
  return out;
}

/**
 * Cards TCGplayer has no price for (every printing blank): use PriceCharting's ungraded price
 * instead, stored as the card's price with source "pricecharting" so it's labelled as such.
 * Only when no printing has a price, since PriceCharting doesn't tell printings apart.
 */
export async function fillMissingPrices(admin: SupabaseClient<Database>): Promise<number> {
  const blank = await selectAll<{ product_id: string; printing: string }>((from, to) =>
    admin.from("product_prices").select("product_id, printing").is("market_price", null).range(from, to),
  50_000);
  const ids = [...new Set(blank.map((r) => r.product_id))];
  let filled = 0;
  for (let i = 0; i < ids.length; i += 300) {
    const chunk = ids.slice(i, i + 300);
    // Leave out any card with a priced printing.
    const { data: priced } = await admin.from("product_prices").select("product_id").in("product_id", chunk).not("market_price", "is", null);
    const pricedIds = new Set((priced ?? []).map((r) => r.product_id));
    const candidates = chunk.filter((id) => !pricedIds.has(id));
    if (!candidates.length) continue;
    const { data: products } = await admin.from("products").select("id, tcgplayer_id").in("id", candidates);
    const byTcg = new Map<number, string>();
    for (const p of products ?? []) if (p.tcgplayer_id) byTcg.set(p.tcgplayer_id, p.id);
    if (!byTcg.size) continue;
    const { data: pc } = await admin.from("pricecharting_prices").select("tcg_id, ungraded, sales_volume").in("tcg_id", [...byTcg.keys()]).not("ungraded", "is", null);
    const best = new Map<number, { ungraded: number; sales: number }>();
    for (const r of pc ?? []) {
      if (r.tcg_id === null || r.ungraded === null) continue;
      const prev = best.get(r.tcg_id);
      if (!prev || (r.sales_volume ?? 0) > prev.sales) best.set(r.tcg_id, { ungraded: Number(r.ungraded), sales: r.sales_volume ?? 0 });
    }
    const now = new Date().toISOString();
    const rows = blank
      .filter((b) => candidates.includes(b.product_id))
      .flatMap((b) => {
        const tcg = [...byTcg.entries()].find(([, id]) => id === b.product_id)?.[0];
        const value = tcg === undefined ? undefined : best.get(tcg)?.ungraded;
        return value ? [{ product_id: b.product_id, printing: b.printing, market_price: value, source: "pricecharting", source_updated_at: now, fetched_at: now, status: "live" as const }] : [];
      });
    if (rows.length) {
      const { error } = await admin.from("product_prices").upsert(rows);
      if (!error) filled += rows.length;
    }
  }
  return filled;
}

/** Download every brand's guide and store it. One request per brand per day. */
export async function syncPriceCharting(admin: SupabaseClient<Database>): Promise<{ category: string; rows: number; error?: string }[]> {
  const token = process.env.PRICECHARTING_TOKEN!;
  const results: { category: string; rows: number; error?: string }[] = [];
  for (const category of PRICECHARTING_CATEGORIES) {
    try {
      const url = `https://www.pricecharting.com/price-guide/download-custom?t=${encodeURIComponent(token)}&category=${category}`;
      const res = await fetch(url, { headers: { "User-Agent": "holo-collection-tracker" }, signal: AbortSignal.timeout(120_000) });
      if (!res.ok) throw new Error(`PriceCharting ${res.status}`);
      const rows = guideRows(await res.text());
      for (let i = 0; i < rows.length; i += 1000) {
        const { error } = await admin.from("pricecharting_prices").upsert(rows.slice(i, i + 1000));
        if (error) throw new Error(error.message);
      }
      results.push({ category, rows: rows.length });
    } catch (e) {
      results.push({ category, rows: 0, error: (e as Error).message });
    }
  }
  return results;
}

/** A slab's grade as PriceCharting prices it: exact for PSA/BGS/CGC/SGC 10, any grader below. */
export function gradeColumn(company: string, grade: string): keyof PriceChartingRow | null {
  const g = Number(grade);
  const c = company.toUpperCase();
  if (g === 10) return c === "PSA" ? "psa_10" : c === "BGS" ? "bgs_10" : c === "CGC" ? "cgc_10" : c === "SGC" ? "sgc_10" : null;
  if (g === 9.5) return "grade_9_5";
  if (g === 9) return "grade_9";
  if (g === 8) return "grade_8";
  if (g === 7) return "grade_7";
  return null;
}
