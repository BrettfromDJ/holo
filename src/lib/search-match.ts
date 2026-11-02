import { normalize } from "./search-query";

/**
 * Search helpers beyond plain words: collector numbers ("215/203", "#215", "TG05") and
 * typo tolerance ("charzard" → Charizard, "vmx" → VMAX). Pure functions, shared by the
 * search route and its tests.
 */

// MARK: Collector numbers

export interface NumberQuery {
  /** Letters before the digits, lowercased ("tg" in TG05; "" for 215). */
  prefix: string;
  /** The digits without leading zeros ("5" for TG05). */
  digits: string;
  /** The set total after "/", when given ("203" in 215/203), split the same way. */
  total: { prefix: string; digits: string } | null;
  /** Typed as a number for sure ("#215", "215/203"); otherwise it may also be a word in a name or set ("151"). */
  explicit: boolean;
}

const PART = /^([a-z]{0,5})(\d{1,4})$/;

function splitPart(part: string): { prefix: string; digits: string } | null {
  const m = PART.exec(part.toLowerCase());
  if (!m) return null;
  return { prefix: m[1], digits: m[2].replace(/^0+(?=\d)/, "") };
}

/**
 * Reads a collector number from one query word: "215/203", "#215", "215", "TG05", "TG05/TG30",
 * "GG12", "SWSH001". Bare digits count only up to three of them ("2023" is a year, not a number).
 */
export function parseNumberToken(token: string): NumberQuery | null {
  let t = token.trim().toLowerCase();
  const hash = t.startsWith("#");
  if (hash) t = t.slice(1);
  const [head, tail, ...rest] = t.split("/");
  if (rest.length || !head) return null;
  const num = splitPart(head);
  if (!num) return null;
  let total: NumberQuery["total"] = null;
  if (tail !== undefined) {
    total = splitPart(tail);
    if (!total) return null;
  }
  // Plain digits: up to three ("4", "25", "215"); longer is likely a year or a code.
  if (!num.prefix && !hash && !total && !/^\d{1,3}$/.test(head)) return null;
  return { ...num, total, explicit: hash || total !== null };
}

/** Takes the first collector number out of the query words; the rest stay words. */
export function splitNumber(words: string[]): { words: string[]; number: NumberQuery | null; numberWord: string | null } {
  for (let i = 0; i < words.length; i++) {
    const n = parseNumberToken(words[i]);
    if (n) return { words: words.filter((_, j) => j !== i), number: n, numberWord: words[i] };
  }
  return { words, number: null, numberWord: null };
}

/**
 * Case-insensitive patterns (PostgREST `ilike`, `*` as the wildcard) that find a number in the
 * `number` column whatever its leading zeros: "15" finds "15", "015/198" and "0015".
 */
export function numberPatterns(n: NumberQuery): string[] {
  const out: string[] = [];
  for (let len = n.digits.length; len <= 4; len++) {
    const padded = `${n.prefix}${"0".repeat(len - n.digits.length)}${n.digits}`;
    out.push(padded, `${padded}/*`);
  }
  return out;
}

/** Whether a stored collector number ("215/203", "TG05/TG30", "SWSH001") is the one asked for. */
export function matchesNumber(value: string | null | undefined, n: NumberQuery): boolean {
  if (!value) return false;
  const [head, tail] = value.trim().toLowerCase().split("/");
  const num = splitPart(head ?? "");
  if (!num || num.prefix !== n.prefix || num.digits !== n.digits) return false;
  if (!n.total) return true;
  // A stored number without a total still matches; with one, it has to agree.
  if (tail === undefined) return true;
  const total = splitPart(tail);
  return !total || (total.prefix === n.total.prefix && total.digits === n.total.digits);
}

// MARK: Typos

/** Edit distance counting a swap of two neighbouring letters as one edit (optimal string alignment). */
export function damerauLevenshtein(a: string, b: string, max = Infinity): number {
  if (a === b) return 0;
  if (Math.abs(a.length - b.length) > max) return max + 1;
  if (!a.length) return b.length;
  if (!b.length) return a.length;
  let prev2: number[] = [];
  let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    const cur = [i];
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      let d = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) d = Math.min(d, prev2[j - 2] + 1);
      cur.push(d);
    }
    prev2 = prev;
    prev = cur;
  }
  return prev[b.length];
}

/** How many edits a word may be off by: none for short words, one up to 7 letters, two from 8. */
export function fuzzyTolerance(word: string): number {
  if (word.length < 3) return 0;
  return word.length >= 8 ? 2 : 1;
}

/** Fuzzy search runs only when a query word is long enough to guess at (4+ letters). */
export function canFuzz(words: string[]): boolean {
  return words.some((w) => /^[a-z]{4,}$/.test(w));
}

/**
 * Short pieces of a word to fetch candidates by (its first and last letters), so a typo
 * anywhere still leaves one piece intact: "chrizard" → "chr", "ard".
 */
export function fuzzyAnchors(word: string): string[] {
  if (word.length >= 4) return [...new Set([word.slice(0, 3), word.slice(-3)])];
  if (word.length === 3) return [...new Set([word.slice(0, 2), word.slice(1)])];
  return [word];
}

/** The closest a query word gets to any of the product's words, or null when none is close enough. */
export function wordDistance(word: string, tokens: string[]): number | null {
  const tol = fuzzyTolerance(word);
  let best: number | null = null;
  for (const t of tokens) {
    if (t === word || (word.length >= 3 && t.startsWith(word))) return 0;
    if (!tol) continue;
    const d = damerauLevenshtein(word, t, tol);
    if (d <= tol && (best === null || d < best)) best = d;
  }
  return best;
}

/** Total edits for every query word to find a match in the text, or null when one doesn't. */
export function fuzzyDistance(text: string, words: string[]): number | null {
  const tokens = normalize(text).split(" ").filter(Boolean);
  let total = 0;
  for (const w of words) {
    const d = wordDistance(w, tokens);
    if (d === null) return null;
    total += d;
  }
  return total;
}

/** Keeps the items whose text is within reach of every word, closest first (ties keep their order). */
export function fuzzyFilter<T>(items: T[], words: string[], textOf: (item: T) => string): T[] {
  return items
    .map((item, i) => ({ item, i, d: fuzzyDistance(textOf(item), words) }))
    .filter((x): x is { item: T; i: number; d: number } => x.d !== null)
    .sort((a, b) => a.d - b.d || a.i - b.i)
    .map((x) => x.item);
}
