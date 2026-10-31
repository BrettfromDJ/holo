import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, PriceChartingRow } from "../supabase/database.types";

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
    if (!Number.isFinite(pcId) || !pcId || !Number.isFinite(tcgId) || !tcgId) continue;
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
      sales_volume: Number(cells[at("sales-volume")]) || null,
      updated_at: now,
    };
    for (const [column, key] of Object.entries(COLUMNS)) (row[key] as number | null) = money(cells[at(column)]);
    out.push(row);
  }
  return out;
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
