import { todayISO } from "./finance/dates";
import { normalize } from "./search-query";
import type { Condition, Grade, ISODate, Product } from "./types";

/**
 * CSV import: turns a spreadsheet or another tracker's export into purchase
 * rows, and ranks catalog products against each row. Pure — no network.
 */

// ---------------------------------------------------------------------------
// CSV text → table

/** Parse CSV text into rows of cells (quoted fields, "" escapes, CRLF, BOM; comma, semicolon or tab). Blank lines are dropped. */
export function parseCsv(text: string): string[][] {
  const src = text.replace(/^﻿/, "");
  const delimiter = detectDelimiter(src);
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = "";
  let quoted = false;
  for (let i = 0; i < src.length; i++) {
    const ch = src[i];
    if (quoted) {
      if (ch === '"') {
        if (src[i + 1] === '"') {
          cell += '"';
          i++;
        } else quoted = false;
      } else cell += ch;
      continue;
    }
    if (ch === '"' && cell.trim() === "") {
      cell = "";
      quoted = true;
    } else if (ch === delimiter) {
      row.push(cell);
      cell = "";
    } else if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && src[i + 1] === "\n") i++;
      row.push(cell);
      rows.push(row);
      row = [];
      cell = "";
    } else cell += ch;
  }
  if (cell !== "" || row.length) {
    row.push(cell);
    rows.push(row);
  }
  return rows.map((r) => r.map((c) => c.trim())).filter((r) => r.some((c) => c !== ""));
}

/** The delimiter used most often on the first line, outside quotes. */
function detectDelimiter(text: string): string {
  const counts: Record<string, number> = { ",": 0, ";": 0, "\t": 0 };
  let quoted = false;
  for (const ch of text) {
    if (ch === '"') quoted = !quoted;
    else if (!quoted && (ch === "\n" || ch === "\r")) break;
    else if (!quoted && ch in counts) counts[ch]++;
  }
  const [best, n] = Object.entries(counts).sort((a, b) => b[1] - a[1])[0];
  return n > 0 ? best : ",";
}

// ---------------------------------------------------------------------------
// Header → fields

export type ImportField = "name" | "set" | "number" | "condition" | "grader" | "grade" | "quantity" | "price" | "total" | "date" | "printing" | "notes" | "source";

const ALIASES: Record<ImportField, string[]> = {
  name: ["name", "card", "card name", "product", "product name", "title", "item", "item name", "cardname"],
  set: ["set", "set name", "expansion", "expansion name", "series", "setname"],
  number: ["number", "card number", "#", "no", "num", "collector number", "card #", "card no", "number in set"],
  condition: ["condition", "cond", "card condition"],
  grader: ["grading company", "grader", "grading service", "graded by", "company", "grading"],
  grade: ["grade", "graded", "slab", "graded grade"],
  quantity: ["quantity", "qty", "count", "copies", "quantity owned", "amount owned", "owned"],
  price: ["price", "price paid", "cost", "purchase price", "unit price", "paid", "buy price", "price each", "cost each", "unit cost", "purchase cost", "cost basis"],
  total: ["total", "total price", "total paid", "total cost", "line total"],
  date: ["date", "purchase date", "acquired", "date acquired", "purchased", "bought", "date purchased", "acquired date", "acquired on", "purchased on", "added", "date added"],
  printing: ["printing", "variant", "finish", "foil", "edition", "variance", "print"],
  notes: ["notes", "note", "comments", "comment"],
  source: ["source", "store", "seller", "bought from", "purchased from", "vendor", "where"],
};

export function normalizeHeader(h: string): string {
  return h
    .toLowerCase()
    .replace(/\(.*?\)|\[.*?\]/g, " ")
    .replace(/[_\-.:]/g, " ")
    .replace(/[^a-z0-9# ]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

export type ColumnMap = Partial<Record<ImportField, number>>;

/** Which column holds which field. The first matching header wins. */
export function detectColumns(header: string[]): ColumnMap {
  const map: ColumnMap = {};
  const norm = header.map(normalizeHeader);
  for (const field of Object.keys(ALIASES) as ImportField[]) {
    const i = norm.findIndex((h, idx) => ALIASES[field].includes(h) && !Object.values(map).includes(idx));
    if (i >= 0) map[field] = i;
  }
  return map;
}

// ---------------------------------------------------------------------------
// Cell values

const CONDITION_WORDS: [RegExp, Condition][] = [
  [/^(sealed|factory sealed|new|nib|brand new|mint sealed)$/, "Sealed"],
  [/^(nm|near mint|mint|m|nm m|nmm|nm mint|near mint or better|gem mint|nm\+?)$/, "Near Mint"],
  [/^(lp|lightly played|light played|light play|ex|excellent|slightly played|sp|lp nm)$/, "Lightly Played"],
  [/^(mp|moderately played|moderate played|moderate play|played|pl|vg|very good|good|gd)$/, "Moderately Played"],
  [/^(hp|heavily played|heavy played|heavy play|poor|fair)$/, "Heavily Played"],
  [/^(dmg|damaged|dm|d|po)$/, "Damaged"],
];

/** NM, Lightly Played, "near-mint"… → the app's condition, or null when blank or unknown. */
export function parseCondition(raw: string | undefined): Condition | null {
  const s = (raw ?? "")
    .toLowerCase()
    .replace(/[-/_]/g, " ")
    .replace(/\s+(holofoil|foil|holo|reverse holofoil|normal)$/, "")
    .replace(/\s+/g, " ")
    .trim();
  if (!s) return null;
  for (const [re, c] of CONDITION_WORDS) if (re.test(s)) return c;
  return null;
}

const GRADER_NAMES: [RegExp, string][] = [
  [/^psa$/, "PSA"],
  [/^(bgs|beckett|bvg)$/, "BGS"],
  [/^cgc$/, "CGC"],
  [/^sgc$/, "SGC"],
  [/^tag$/, "TAG"],
  [/^(ace|ags|gma|hga|isa|mnt)$/, ""],
];

function graderName(raw: string): string | null {
  const s = raw.trim().toLowerCase();
  if (!s) return null;
  for (const [re, name] of GRADER_NAMES) if (re.test(s)) return name || s.toUpperCase();
  return null;
}

const UNGRADED = /^(raw|ungraded|none|no|n\/a|na|-|not graded|0)$/i;

/** A grade number: 10, 9.5, "Gem Mint 10", "Pristine 10" → "10". */
function gradeNumber(raw: string): string | null {
  const m = raw.match(/(^|[^\d.])(10|[1-9](?:\.5)?)(?![\d])/);
  return m ? m[2] : null;
}

/**
 * The grade, from a grader column plus a grade column, or from one cell such
 * as "PSA 10", "BGS 9.5 Black Label" or "CGC Pristine 10". A grade with no
 * known grading company is not a grade (returns null).
 */
export function parseGrade(graderCell: string | undefined, gradeCell: string | undefined): Grade | null {
  const gradeRaw = (gradeCell ?? "").trim();
  const graderRaw = (graderCell ?? "").trim();
  if (UNGRADED.test(gradeRaw) || UNGRADED.test(graderRaw)) return null;
  // "PSA 10" in either cell.
  for (const cell of [gradeRaw, graderRaw]) {
    const m = cell.match(/^([a-z]+)\s*[- ]?\s*(.*)$/i);
    if (m) {
      const company = graderName(m[1]);
      const n = company ? gradeNumber(m[2]) : null;
      if (company && n) return { company, grade: n };
    }
  }
  const company = graderName(graderRaw);
  const n = gradeNumber(gradeRaw);
  if (company && n) return { company, grade: n };
  return null;
}

/** "$1,234.50", "USD 12", "12.00 $" → 1234.5. Null when blank or not a price. */
export function parsePrice(raw: string | undefined): number | null {
  let s = (raw ?? "").trim();
  if (!s) return null;
  s = s.replace(/[^0-9.,-]/g, "");
  // "12,50" (decimal comma, no dot) → 12.50; otherwise commas are thousands separators.
  if (/^\d+,\d{1,2}$/.test(s)) s = s.replace(",", ".");
  else s = s.replace(/,/g, "");
  if (!s || s.startsWith("-")) return null;
  const n = Number(s);
  return Number.isFinite(n) ? Math.round(n * 10000) / 10000 : null;
}

/** "3", "x3", "3x", "3.0" → 3. Blank → 1. Null when not a positive whole number. */
export function parseQuantity(raw: string | undefined): number | null {
  const s = (raw ?? "").trim().toLowerCase().replace(/^x\s*|\s*x$/g, "").replace(/,/g, "");
  if (!s) return 1;
  const n = Number(s);
  if (!Number.isFinite(n) || n < 1 || Math.round(n) !== n) return null;
  return n;
}

const MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];

function iso(y: number, m: number, d: number): ISODate | null {
  if (y < 100) y += y >= 70 ? 1900 : 2000;
  if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1990 || y > 2100) return null;
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (dt.getUTCMonth() !== m - 1) return null; // e.g. Feb 30
  return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

/**
 * YYYY-MM-DD (with or without a time), YYYY/MM/DD, M/D/YYYY, M-D-YY,
 * D.M.YYYY, "Jan 5, 2024", "5 January 2024". Slashed dates are month first
 * unless the first number can't be a month. Null when blank or unreadable.
 */
export function parseDate(raw: string | undefined): ISODate | null {
  const s = (raw ?? "").trim();
  if (!s) return null;
  let m = s.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[ T].*)?$/);
  if (m) return iso(+m[1], +m[2], +m[3]);
  m = s.match(/^(\d{1,2})\.(\d{1,2})\.(\d{2,4})$/);
  if (m) return iso(+m[3], +m[2], +m[1]);
  m = s.match(/^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})(?:\s.*)?$/);
  if (m) {
    const a = +m[1];
    const b = +m[2];
    return a > 12 ? iso(+m[3], b, a) : iso(+m[3], a, b);
  }
  m = s.match(/^([a-z]{3,})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{2,4})$/i);
  if (m) {
    const mo = MONTHS.indexOf(m[1].slice(0, 3).toLowerCase());
    return mo >= 0 ? iso(+m[3], mo + 1, +m[2]) : null;
  }
  m = s.match(/^(\d{1,2})(?:st|nd|rd|th)?\s+([a-z]{3,})\.?,?\s+(\d{2,4})$/i);
  if (m) {
    const mo = MONTHS.indexOf(m[2].slice(0, 3).toLowerCase());
    return mo >= 0 ? iso(+m[3], mo + 1, +m[1]) : null;
  }
  return null;
}

/** Holo, Reverse Holo, Non-foil, 1st Ed… → the catalog's printing names. Null when blank. */
export function parsePrinting(raw: string | undefined): string | null {
  const s = (raw ?? "").toLowerCase().replace(/[-_]/g, " ").replace(/\s+/g, " ").trim();
  if (!s || /^(n\/a|none|-)$/.test(s)) return null;
  const first = /\b(1st|first)( ed(ition)?)?\b/.test(s);
  const unlimited = /\bunlimited\b/.test(s);
  let finish: string | null = null;
  if (/\b(reverse|rev|rh)\b/.test(s)) finish = "Reverse Holofoil";
  else if (/\b(non ?holo|non ?foil|normal|regular|standard|nonfoil|nonholo)\b/.test(s)) finish = "Normal";
  else if (/\b(holo|holofoil|foil)\b/.test(s)) finish = "Holofoil";
  const edition = first ? "1st Edition" : unlimited ? "Unlimited" : null;
  if (edition && finish) return `${edition} ${finish}`;
  if (edition) return edition;
  if (finish) return finish;
  // Anything else (e.g. "Cosmos Holo" was caught above; "Pokeball Pattern") is kept as typed.
  return raw!.trim();
}

/** The product's printing closest to what the CSV asked for. Falls back to `fallback` (the priced printing) when nothing fits. */
export function matchPrinting(wanted: string | null, available: string[], fallback: string | null = null): { printing: string | null; matched: boolean } {
  const base = fallback ?? available[0] ?? null;
  if (!wanted) return { printing: base, matched: true };
  if (!available.length) return { printing: base ?? wanted, matched: !base || base.toLowerCase() === wanted.toLowerCase() };
  const w = wanted.toLowerCase();
  const exact = available.find((p) => p.toLowerCase() === w);
  if (exact) return { printing: exact, matched: true };
  const words = w.split(" ");
  // "1st Edition" → "1st Edition Holofoil"; "Holofoil" → "Unlimited Holofoil", never "Reverse Holofoil".
  const scored = available
    .map((p) => {
      const pw = p.toLowerCase().split(" ");
      if (!words.every((x) => pw.includes(x))) return { p, s: -1 };
      if (pw.includes("reverse") && !words.includes("reverse")) return { p, s: -1 };
      return { p, s: words.length / pw.length };
    })
    .filter((x) => x.s > 0)
    .sort((a, b) => b.s - a.s);
  if (scored.length) return { printing: scored[0].p, matched: true };
  return { printing: base, matched: false };
}

// ---------------------------------------------------------------------------
// Rows

export interface ImportRow {
  /** 1-based line in the file (header is line 1). */
  line: number;
  name: string;
  set: string | null;
  number: string | null;
  /** Null when the CSV doesn't say; the importer picks Sealed or Near Mint from the product. */
  condition: Condition | null;
  grade: Grade | null;
  quantity: number;
  /** Per unit. Null when the CSV has no price (the importer uses the market price). */
  unitPrice: number | null;
  date: ISODate;
  printing: string | null;
  notes: string | null;
  source: string | null;
  warnings: string[];
}

export interface SkippedLine {
  line: number;
  reason: string;
}

export interface ParsedImport {
  columns: ColumnMap;
  rows: ImportRow[];
  skipped: SkippedLine[];
  /** Set when the file can't be used at all. */
  error: string | null;
}

/** "Charizard ex - 199/165" or "Pikachu #25" → the number at the end of a card name. */
export function numberFromName(name: string): string | null {
  const m = name.match(/(?:\s-\s|#|\s)([A-Za-z]{0,4}\d{1,4}[a-z]?\/[A-Za-z]{0,4}\d{1,4})\s*$/) ?? name.match(/#\s*([A-Za-z]{0,4}\d{1,4}[a-z]?)\s*$/);
  return m ? m[1] : null;
}

/** Parse a whole CSV file into import rows. */
export function parseImport(text: string, today: ISODate = todayISO()): ParsedImport {
  const table = parseCsv(text);
  const empty: ParsedImport = { columns: {}, rows: [], skipped: [], error: null };
  if (!table.length) return { ...empty, error: "The file is empty." };
  const columns = detectColumns(table[0]);
  if (columns.name === undefined) {
    return { ...empty, columns, error: "Couldn't find a name column. Add a header row with a column called Name (or Card, Product, Title)." };
  }
  const rows: ImportRow[] = [];
  const skipped: SkippedLine[] = [];
  const cell = (r: string[], f: ImportField) => (columns[f] === undefined ? undefined : r[columns[f]!]);

  table.slice(1).forEach((r, i) => {
    const line = i + 2;
    const name = (cell(r, "name") ?? "").trim();
    if (!name) {
      skipped.push({ line, reason: "No name" });
      return;
    }
    const warnings: string[] = [];
    const quantity = parseQuantity(cell(r, "quantity"));
    if (quantity === null) {
      skipped.push({ line, reason: `Quantity "${cell(r, "quantity")}" isn't a whole number` });
      return;
    }

    let unitPrice = parsePrice(cell(r, "price"));
    if (unitPrice === null) {
      const total = parsePrice(cell(r, "total"));
      if (total !== null) unitPrice = Math.round((total / quantity) * 10000) / 10000;
    }
    if (unitPrice === null && (cell(r, "price") ?? cell(r, "total") ?? "").trim()) warnings.push("Couldn't read the price");

    const rawDate = cell(r, "date");
    let date = parseDate(rawDate);
    if (!date) {
      if ((rawDate ?? "").trim()) warnings.push(`Couldn't read the date "${rawDate}", used today`);
      date = today;
    } else if (date > today) {
      warnings.push("Date is in the future, used today");
      date = today;
    }

    const conditionCell = cell(r, "condition");
    // A grade can hide in the condition column too ("PSA 10").
    const grade = parseGrade(cell(r, "grader"), cell(r, "grade")) ?? parseGrade(undefined, conditionCell);
    const condition = grade ? null : parseCondition(conditionCell);
    if (!grade && !condition && (conditionCell ?? "").trim()) warnings.push(`Unknown condition "${conditionCell}", used Near Mint`);
    if (!grade && (cell(r, "grade") ?? "").trim() && !UNGRADED.test(cell(r, "grade")!.trim()) && gradeNumber(cell(r, "grade")!)) {
      warnings.push("Grade without a grading company, imported as raw");
    }

    const number = (cell(r, "number") ?? "").replace(/^#/, "").trim() || numberFromName(name);
    rows.push({
      line,
      name,
      set: (cell(r, "set") ?? "").trim() || null,
      number: number || null,
      condition,
      grade,
      quantity,
      unitPrice,
      date,
      printing: parsePrinting(cell(r, "printing")),
      notes: (cell(r, "notes") ?? "").trim() || null,
      source: (cell(r, "source") ?? "").trim() || null,
      warnings,
    });
  });
  if (!rows.length && !skipped.length) return { ...empty, columns, error: "There are no rows under the header." };
  return { columns, rows, skipped, error: null };
}

// ---------------------------------------------------------------------------
// Matching

/** "199/165" → "199"; "SV049" → "sv49"; "025" → "25". */
export function normalizeNumber(n: string | null | undefined): string | null {
  if (!n) return null;
  const first = n.toLowerCase().replace(/\s+/g, "").split("/")[0].replace(/^#/, "");
  const m = first.match(/^([a-z]*)0*(\d+)([a-z]*)$/);
  return m ? `${m[1]}${m[2]}${m[3]}` : first || null;
}

const SET_FILLER = new Set(["pokemon", "tcg", "the", "and", "set", "expansion", "english", "sv", "swsh", "sm", "xy", "scarlet", "violet", "sword", "shield"]);

function words(s: string, filler?: Set<string>): string[] {
  return normalize(s)
    .replace(/[#/-]/g, " ")
    .split(" ")
    .filter((w) => w && (!filler || !filler.has(w)));
}

/** The card name without its trailing number ("Charizard ex - 199/165" → "charizard ex"), for searching and comparing. */
export function coreName(name: string): string {
  const num = numberFromName(name);
  let s = num ? name.slice(0, name.lastIndexOf(num)) : name;
  s = s.replace(/\s-\s*$|#\s*$/, "");
  return normalize(s).replace(/[#/]/g, " ").replace(/\s+/g, " ").trim();
}

export interface CandidateScore {
  score: number;
  /** Share of the CSV name's words found in the product's name or set (0–1). */
  nameScore: number;
  numberMatch: boolean | null;
  setMatch: boolean | null;
}

/** How well a catalog product fits a CSV row: name words, then number and set. */
export function scoreCandidate(row: Pick<ImportRow, "name" | "set" | "number">, product: Pick<Product, "name" | "setName" | "number">): CandidateScore {
  const want = words(coreName(row.name), new Set(["pokemon", "card", "the"]));
  const productName = coreName(product.name);
  const have = new Set(words(`${productName} ${product.setName ?? ""}`));
  let hits = 0;
  for (const w of want) if (have.has(w)) hits += 1;
  const nameScore = want.length ? hits / want.length : 0;
  // Fewer extra words in the product name is a closer match ("Charizard" vs "Charizard ex").
  const extra = words(productName).filter((w) => !want.includes(w)).length;

  const rowNum = normalizeNumber(row.number);
  const prodNum = normalizeNumber(product.number ?? numberFromName(product.name));
  const numberMatch = rowNum && prodNum ? rowNum === prodNum : null;

  let setMatch: boolean | null = null;
  let setScore = 0;
  if (row.set && product.setName) {
    const a = words(row.set, SET_FILLER);
    const b = new Set(words(product.setName, SET_FILLER));
    const aAll = words(row.set);
    const bAll = new Set(words(product.setName));
    const overlap = a.length ? a.filter((w) => b.has(w)).length / a.length : aAll.filter((w) => bAll.has(w)).length / Math.max(1, aAll.length);
    setScore = overlap;
    setMatch = overlap >= 0.6;
  }

  let score = nameScore * 0.6 - Math.min(0.15, extra * 0.03);
  if (numberMatch === true) score += 0.3;
  if (numberMatch === false) score -= 0.25;
  if (row.set && product.setName) score += 0.25 * setScore - (setMatch ? 0 : 0.05);
  return { score, nameScore, numberMatch, setMatch };
}

/** Candidates that plausibly are this row, best first. */
export function rankCandidates<T extends { product: Pick<Product, "name" | "setName" | "number"> }>(row: Pick<ImportRow, "name" | "set" | "number">, items: T[]): (T & { fit: CandidateScore })[] {
  return items
    .map((item, i) => ({ out: { ...item, fit: scoreCandidate(row, item.product) }, i }))
    .filter((x) => x.out.fit.nameScore >= 0.5)
    .sort((a, b) => b.out.fit.score - a.out.fit.score || a.i - b.i)
    .map((x) => x.out);
}

/** True when the best candidate is clearly this row: number and set agree where the CSV gives them. */
export function isConfident(fit: CandidateScore): boolean {
  return fit.nameScore >= 0.99 && fit.numberMatch !== false && fit.setMatch !== false;
}

/** Stored-catalog search strings for a row, most specific first. */
export function searchQueries(row: Pick<ImportRow, "name" | "set" | "number">): string[] {
  const core = coreName(row.name);
  const qs: string[] = [];
  const push = (q: string) => {
    const s = q.replace(/\s+/g, " ").trim();
    if (s.length >= 3 && !qs.includes(s)) qs.push(s);
  };
  if (row.number && row.number.includes("/")) push(`${core} ${row.number.replace(/\s+/g, "")}`);
  if (row.set) push(`${core} ${words(row.set, SET_FILLER).join(" ")}`);
  push(core);
  return qs;
}

// ---------------------------------------------------------------------------
// Duplicates

/** A purchase as it would be saved (or as it is in the collection). */
export interface PurchaseLike {
  productId: string;
  printing: string | null;
  condition: Condition;
  grade: Grade | null;
  date: ISODate;
  quantity: number;
  unitPrice: number;
}

function sameGrade(a: Grade | null, b: Grade | null): boolean {
  if (!a || !b) return !a && !b;
  return a.company.toLowerCase() === b.company.toLowerCase() && Number(a.grade) === Number(b.grade);
}

/**
 * True when two purchases are the same buy: same product, printing,
 * condition (or grade, for slabs), date and quantity, and unit price within $0.01.
 */
export function samePurchase(a: PurchaseLike, b: PurchaseLike): boolean {
  return (
    a.productId === b.productId &&
    (a.printing ?? "").toLowerCase() === (b.printing ?? "").toLowerCase() &&
    sameGrade(a.grade, b.grade) &&
    (a.grade ? true : a.condition === b.condition) &&
    a.date === b.date &&
    a.quantity === b.quantity &&
    Math.abs(a.unitPrice - b.unitPrice) <= 0.01 + 1e-9
  );
}

/**
 * Which rows are already in the collection. Each existing purchase accounts
 * for one row at most, so a file with the same buy twice and a collection
 * holding it once flags only the first. Null rows (skipped) are never flagged.
 */
export function findDuplicates(rows: (PurchaseLike | null)[], existing: PurchaseLike[]): boolean[] {
  const used = new Set<number>();
  return rows.map((row) => {
    if (!row) return false;
    const i = existing.findIndex((e, idx) => !used.has(idx) && samePurchase(row, e));
    if (i < 0) return false;
    used.add(i);
    return true;
  });
}

// ---------------------------------------------------------------------------
// Template

export const TEMPLATE_CSV = [
  "Name,Set,Number,Printing,Condition,Grading company,Grade,Quantity,Price paid,Purchase date,Notes",
  "Charizard ex,Obsidian Flames,223/197,Holofoil,NM,,,1,72.00,2024-03-14,",
  "Umbreon VMAX (Alternate Full Art),Evolving Skies,215/203,Holofoil,,PSA,10,1,\"1,250.00\",2024-06-02,Graded",
  "Evolving Skies Booster Box,Evolving Skies,,,Sealed,,,2,640.00,1/15/2023,",
  "",
].join("\n");
