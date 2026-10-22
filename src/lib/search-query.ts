import { categoryOf, type ProductCategory } from "./catalog";
import type { Product } from "./types";

/**
 * Turns what a collector types into search attempts the catalog is likely to
 * match. Catalog search matches names fairly literally, so a phrase such as
 * "30th anniversary etb" may return nothing even though the product exists.
 * We expand abbreviations, separate the product-type phrase from the
 * distinguishing words, and produce progressively looser variants.
 */

const ABBREVIATIONS: [RegExp, string][] = [
  [/\betbs?\b/g, "elite trainer box"],
  [/\bupcs?\b/g, "ultra premium collection"],
  [/\bbbs?\b/g, "booster box"],
  [/\bsir\b/g, "special illustration rare"],
  [/\bsv\b/g, "scarlet violet"],
  [/\bswsh\b/g, "sword shield"],
];

const CATEGORY_PHRASES: [RegExp, ProductCategory][] = [
  [/\bultra premium collection\b/, "Ultra Premium Collection"],
  [/\belite trainer box\b/, "Elite Trainer Box"],
  [/\b(booster )?bundles?\b/, "Booster Bundle"],
  [/\bbooster (box|display)\b/, "Booster Box"],
  [/\b(booster )?packs?\b/, "Booster Pack"],
  [/\btins?\b/, "Tin"],
  [/\b(premium |special )?collection( box)?\b/, "Collection Box"],
];

const STOPWORDS = new Set(["pokemon", "pokémon", "tcg", "the", "a", "an", "of", "english", "new", "sealed", "and", "card", "cards"]);

export interface ParsedQuery {
  /** Normalized full query (abbreviations expanded). */
  text: string;
  /** Product type named in the query, if any. */
  category: ProductCategory | null;
  /** Distinguishing words with the product-type phrase and filler removed. */
  core: string;
  /** Tokens used for ranking. */
  tokens: string[];
  /** Ordered, de-duplicated search strings from strict to loose. */
  variants: string[];
}

export function normalize(text: string): string {
  return text
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[’']/g, "")
    .replace(/[^a-z0-9#/\-\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

export function parseQuery(raw: string): ParsedQuery {
  let text = normalize(raw);
  for (const [re, rep] of ABBREVIATIONS) text = text.replace(re, rep);
  text = text.replace(/\s+/g, " ").trim();

  let category: ProductCategory | null = null;
  let rest = text;
  for (const [re, cat] of CATEGORY_PHRASES) {
    if (re.test(rest)) {
      category = cat;
      rest = rest.replace(re, " ");
      break;
    }
  }
  const coreTokens = rest.split(" ").filter((t) => t && !STOPWORDS.has(t));
  const core = coreTokens.join(" ");
  const tokens = text.split(" ").filter((t) => t && !STOPWORDS.has(t));

  const variants: string[] = [];
  const push = (v: string) => {
    const s = v.trim();
    if (s.length >= 2 && !variants.includes(s)) variants.push(s);
  };
  push(text);
  if (core && category) push(`${core} ${category.toLowerCase()}`);
  push(core);
  // Long phrases rarely match verbatim; try the leading and trailing pairs
  // ("scarlet violet …" / "… prismatic evolutions").
  if (coreTokens.length > 2) {
    push(coreTokens.slice(-2).join(" "));
    push(coreTokens.slice(0, 2).join(" "));
  }
  return { text, category, core, tokens, variants };
}

/**
 * Relevance of a catalog product for a parsed query, roughly 0–1.1.
 * Distinguishing words (set, Pokémon, product name) outweigh the product-type
 * phrase, so "evolving skies etb" prefers Evolving Skies products over other
 * sets' Elite Trainer Boxes.
 */
export function scoreProduct(product: Pick<Product, "name" | "setName" | "productType" | "kind">, q: ParsedQuery): number {
  const hay = normalize(`${product.name} ${product.setName ?? ""} ${product.productType ?? ""}`);
  const words = new Set(hay.split(" "));
  const coreTokens = q.core.split(" ").filter(Boolean);
  const catMatch = q.category ? (categoryOf(product) === q.category ? 1 : 0) : 0;
  if (!coreTokens.length) return q.category ? catMatch : 0;

  let hits = 0;
  for (const t of coreTokens) {
    if (words.has(t)) hits += 1;
    else if (t.length >= 3 && hay.includes(t)) hits += 0.7;
  }
  const coreFrac = hits / coreTokens.length;
  let score = q.category ? 0.7 * coreFrac + 0.3 * catMatch : coreFrac;
  if (normalize(product.name).includes(q.core)) score += 0.1;
  return score;
}

/** Sort by relevance, keeping the source order for ties. */
export function rankByQuery<T extends { product: Product }>(items: T[], q: ParsedQuery): T[] {
  return items
    .map((item, i) => ({ item, i, s: scoreProduct(item.product, q) }))
    .sort((a, b) => b.s - a.s || a.i - b.i)
    .map((x) => x.item);
}
