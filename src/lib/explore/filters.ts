import type { ExploreProduct } from "./types";

/** Filters and sort for catalog search results (applied in the browser to the top matches). */
export interface SearchFilters {
  type: "all" | "single" | "sealed";
  language: string | null;
  brand: string | null;
  owned: "any" | "owned" | "not-owned";
  watchlist: boolean;
  min: number | null;
  max: number | null;
  sort: "match" | "price-desc" | "price-asc" | "name";
}

export const NO_FILTERS: SearchFilters = { type: "all", language: null, brand: null, owned: "any", watchlist: false, min: null, max: null, sort: "match" };

/** A catalog's language, from its name ("Pokemon Japan" is Japanese); catalogs without one are English. */
export function languageOf(gameName: string | null | undefined): string {
  const g = (gameName ?? "").toLowerCase();
  if (/japan/.test(g)) return "Japanese";
  if (/chin/.test(g)) return "Chinese";
  if (/korea/.test(g)) return "Korean";
  return "English";
}

/** The base brand without its language ("Pokemon Japan" → "Pokemon"). */
export function brandOf(gameName: string | null | undefined): string | null {
  if (!gameName) return null;
  return gameName.replace(/\s+(japan(ese)?|chinese|china|korea(n)?)$/i, "").trim() || gameName;
}

/** Each value present in the results, with how many results have it, most common first. */
export function facet(items: ExploreProduct[], key: (i: ExploreProduct) => string | null): { value: string; count: number }[] {
  const counts = new Map<string, number>();
  for (const i of items) {
    const v = key(i);
    if (v) counts.set(v, (counts.get(v) ?? 0) + 1);
  }
  return [...counts].map(([value, count]) => ({ value, count })).sort((a, b) => b.count - a.count || a.value.localeCompare(b.value));
}

export function activeFilterCount(f: SearchFilters): number {
  return [f.type !== "all", f.language, f.brand, f.owned !== "any", f.watchlist, f.min !== null || f.max !== null].filter(Boolean).length;
}

export function applyFilters(items: ExploreProduct[], f: SearchFilters, ctx: { owned: Set<string>; watched: Set<string> }): ExploreProduct[] {
  const out = items.filter((i) => {
    const p = i.product;
    if (f.type !== "all" && p.kind !== f.type) return false;
    if (f.language && languageOf(i.gameName) !== f.language) return false;
    if (f.brand && brandOf(i.gameName) !== f.brand) return false;
    if (f.owned === "owned" && !ctx.owned.has(p.id)) return false;
    if (f.owned === "not-owned" && ctx.owned.has(p.id)) return false;
    if (f.watchlist && !ctx.watched.has(p.id)) return false;
    // A price range leaves out unpriced items.
    if ((f.min !== null || f.max !== null) && i.market === null) return false;
    if (f.min !== null && i.market! < f.min) return false;
    if (f.max !== null && i.market! > f.max) return false;
    return true;
  });
  if (f.sort === "match") return out;
  const priced = (i: ExploreProduct, dir: 1 | -1) => (i.market === null ? Infinity : dir * i.market);
  return [...out].sort((a, b) =>
    f.sort === "name" ? a.product.name.localeCompare(b.product.name) : f.sort === "price-asc" ? priced(a, 1) - priced(b, 1) : priced(a, -1) - priced(b, -1),
  );
}
