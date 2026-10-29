import { describe, expect, it } from "vitest";
import type { Product } from "../types";
import { applyFilters, brandOf, facet, languageOf, NO_FILTERS } from "./filters";
import type { ExploreProduct } from "./types";

const item = (id: string, kind: "single" | "sealed", market: number | null, gameName: string): ExploreProduct => ({
  product: { id, name: id, kind } as Product,
  printing: null,
  market,
  priceUpdatedAt: null,
  gameName,
});
const items = [item("a", "single", 10, "Pokemon"), item("b", "sealed", 120, "Pokemon Japan"), item("c", "single", null, "Magic: The Gathering"), item("d", "single", 50, "Pokemon Japan")];
const ctx = { owned: new Set(["a"]), watched: new Set(["d"]) };
const ids = (r: ExploreProduct[]) => r.map((i) => i.product.id);

describe("search filters", () => {
  it("reads language and brand from the catalog name", () => {
    expect(languageOf("Pokemon Japan")).toBe("Japanese");
    expect(languageOf("Pokemon")).toBe("English");
    expect(brandOf("Pokemon Japan")).toBe("Pokemon");
    expect(facet(items, (i) => languageOf(i.gameName))).toEqual([
      { value: "English", count: 2 },
      { value: "Japanese", count: 2 },
    ]);
  });

  it("filters by type, language, ownership, watchlist and price", () => {
    expect(ids(applyFilters(items, { ...NO_FILTERS, type: "sealed" }, ctx))).toEqual(["b"]);
    expect(ids(applyFilters(items, { ...NO_FILTERS, language: "Japanese", type: "single" }, ctx))).toEqual(["d"]);
    expect(ids(applyFilters(items, { ...NO_FILTERS, owned: "not-owned" }, ctx))).toEqual(["b", "c", "d"]);
    expect(ids(applyFilters(items, { ...NO_FILTERS, watchlist: true }, ctx))).toEqual(["d"]);
    expect(ids(applyFilters(items, { ...NO_FILTERS, min: 20 }, ctx))).toEqual(["b", "d"]);
  });

  it("sorts by price with unpriced items last", () => {
    expect(ids(applyFilters(items, { ...NO_FILTERS, sort: "price-desc" }, ctx))).toEqual(["b", "d", "a", "c"]);
    expect(ids(applyFilters(items, { ...NO_FILTERS, sort: "price-asc" }, ctx))).toEqual(["a", "d", "b", "c"]);
  });
});
