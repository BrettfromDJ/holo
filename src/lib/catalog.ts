import type { Product, ProductKind } from "./types";

/**
 * Display categories. These are labels for browsing and filtering only —
 * product identity always comes from the source's numeric id, never names.
 */
export const PRODUCT_CATEGORIES = [
  "Card",
  "Booster Box",
  "Elite Trainer Box",
  "Ultra Premium Collection",
  "Booster Bundle",
  "Collection Box",
  "Tin",
  "Booster Pack",
  "Other Sealed",
] as const;

export type ProductCategory = (typeof PRODUCT_CATEGORIES)[number];

const RULES: [RegExp, ProductCategory][] = [
  [/ultra[- ]premium collection|\bupc\b/i, "Ultra Premium Collection"],
  [/elite trainer box|\betb\b/i, "Elite Trainer Box"],
  [/booster bundle/i, "Booster Bundle"],
  [/booster box|booster display|display box/i, "Booster Box"],
  [/\btin\b/i, "Tin"],
  [/collection|premium box|box set|\bbox\b/i, "Collection Box"],
  [/booster pack|sleeved booster|\bblister\b|\bpack\b/i, "Booster Pack"],
];

/** Classify a product for display. Prefers the source's own product type. */
export function categoryOf(product: Pick<Product, "name" | "productType" | "kind">): ProductCategory {
  if (product.kind === "single") return "Card";
  const haystack = `${product.productType ?? ""} ${product.name}`;
  for (const [re, cat] of RULES) if (re.test(haystack)) return cat;
  return "Other Sealed";
}

/**
 * Determine whether a TCG API record is sealed. The API distinguishes
 * "Cards" from "Sealed Products" via the `type` filter; records returned under
 * `type=Sealed Products` are flagged sealed explicitly by the caller. Without
 * that signal, a product with no collector number and a sealed-sounding name is
 * treated as sealed.
 */
export function inferKind(input: { productType: string | null; number: string | null; name: string }, hint?: ProductKind): ProductKind {
  if (hint) return hint;
  const t = input.productType?.toLowerCase() ?? "";
  if (t.includes("sealed")) return "sealed";
  if (t === "cards" || t === "card" || t.includes("single")) return "single";
  if (input.number) return "single";
  return RULES.some(([re]) => re.test(input.name)) ? "sealed" : "single";
}

export function productSubtitle(product: Product): string {
  return [product.setName, product.number ? `#${product.number}` : null].filter(Boolean).join(" · ");
}
