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
 * Phrases that only ever describe sealed product. Matched against the name
 * with any "(…)" suffix removed, so card names like "Charizard (Classic
 * Collection)" stay singles.
 */
const SEALED_NAME =
  /\b(booster (box|bundle|pack|display|case)|elite trainer box|etb|ultra[- ]premium collection|premium collection|illustration collection|special collection|collection box|binder collection|poster collection|figure collection|pin collection|(mini |stacking )?tins?|blister|build (&|and) battle|trainer box|gift (set|box)|deck box|theme deck|starter deck|battle deck|league battle deck|display box|sleeved booster|surprise box|collector chest|booster bundle|bundle)\b/i;

export function looksSealed(name: string): boolean {
  return SEALED_NAME.test(name.replace(/\([^)]*\)/g, " "));
}

/**
 * Determine whether a catalog record is sealed. Order of evidence:
 * an explicit hint (the search was filtered to Cards or Sealed), the source's
 * product type when it says "sealed", an unmistakably sealed name, then the
 * source's "cards" type or a collector number, then looser name rules.
 */
export function inferKind(input: { productType: string | null; number: string | null; name: string }, hint?: ProductKind): ProductKind {
  if (hint) return hint;
  const t = input.productType?.toLowerCase() ?? "";
  if (t.includes("sealed")) return "sealed";
  if (looksSealed(input.name)) return "sealed";
  if (t === "cards" || t === "card" || t.includes("single")) return "single";
  if (input.number) return "single";
  return RULES.some(([re]) => re.test(input.name)) ? "sealed" : "single";
}

export function productSubtitle(product: Product): string {
  return [product.setName, product.number ? `#${product.number}` : null].filter(Boolean).join(" · ");
}
