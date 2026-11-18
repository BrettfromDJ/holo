import { describe, expect, it } from "vitest";
import { THEMES, fits, orList, pickFor, type ThemeRule } from "./themes";
import type { ExploreProduct } from "./types";

const card = (id: string, name: string, set: string, market: number, releaseDate: string, extra: Partial<ExploreProduct["product"]> = {}): ExploreProduct => ({
  product: { id, source: "tcgapi", externalId: id, name, setName: set, setId: set, number: "1", rarity: "Holo Rare", productType: null, kind: "single", imageUrl: null, tcgplayerId: null, tcgplayerUrl: null, printings: [], ...extra },
  printing: "Holofoil",
  market,
  priceUpdatedAt: null,
  gameName: "Pokemon",
  releaseDate,
});

describe("themes", () => {
  it("has unique ids", () => {
    expect(new Set(THEMES.map((t) => t.id)).size).toBe(THEMES.length);
  });

  it("matches names as whole words", () => {
    const mew: ThemeRule = { id: "m", title: "", blurb: "", look: "timeline", names: ["Mew"] };
    expect(fits(mew, card("1", "Mew ex", "151", 10, "2023-09-22"))).toBe(true);
    expect(fits(mew, card("2", "Mewtwo", "Base Set", 10, "1999-01-09"))).toBe(false);
  });

  it("keeps to price, era and Pokémon games", () => {
    const rule: ThemeRule = { id: "v", title: "", blurb: "", look: "fan", rarities: ["Holo"], era: "vintage", minPrice: 10, maxPrice: 40 };
    expect(fits(rule, card("1", "Gengar", "Fossil", 30, "1999-10-10"))).toBe(true);
    expect(fits(rule, card("2", "Gengar", "Fossil", 50, "1999-10-10"))).toBe(false);
    expect(fits(rule, card("3", "Gengar", "Lost Origin", 30, "2022-09-09"))).toBe(false);
    expect(fits(rule, { ...card("4", "Gengar", "Fossil", 30, "1999-10-10"), gameName: "Magic" })).toBe(false);
  });

  it("timeline: one card per set, oldest first", () => {
    const rule: ThemeRule = { id: "c", title: "", blurb: "", look: "timeline", names: ["Charizard"] };
    const out = pickFor(rule, [
      card("a", "Charizard", "Base Set", 400, "1999-01-09"),
      card("b", "Charizard ex", "151", 100, "2023-09-22"),
      card("c", "Charizard", "Base Set", 300, "1999-01-09"),
    ]);
    expect(out.map((p) => p.product.id)).toEqual(["a", "b"]);
  });

  it("ladder: cheapest to priciest", () => {
    const rule: ThemeRule = { id: "g", title: "", blurb: "", look: "ladder", names: ["Gengar"] };
    const out = pickFor(rule, [card("a", "Gengar", "X", 50, "2000-01-01"), card("b", "Gengar", "Y", 5, "2000-01-01"), card("c", "Gengar", "Z", 500, "2000-01-01")]);
    expect(out.map((p) => p.market)).toEqual([5, 50, 500]);
  });

  it("builds database filters", () => {
    expect(orList("name", ["Dark ", "Shining"])).toBe("name.ilike.*Dark *,name.ilike.*Shining*");
    expect(orList("number", ["TG"], true)).toBe("number.ilike.TG*");
  });
});
