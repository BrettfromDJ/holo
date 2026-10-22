import { describe, expect, it } from "vitest";
import { parseQuery, rankByQuery } from "./search-query";
import type { Product } from "./types";

const p = (name: string, setName: string, kind: Product["kind"] = "sealed"): { product: Product } => ({
  product: { id: name, source: "tcgapi", externalId: "1", name, setName, setId: null, number: null, rarity: null, productType: null, kind, imageUrl: null, tcgplayerId: null, tcgplayerUrl: null },
});

describe("parseQuery", () => {
  it("expands abbreviations and separates the product type", () => {
    const q = parseQuery("30th Anniversary ETB");
    expect(q.text).toBe("30th anniversary elite trainer box");
    expect(q.category).toBe("Elite Trainer Box");
    expect(q.core).toBe("30th anniversary");
    expect(q.variants).toEqual(["30th anniversary elite trainer box", "30th anniversary"]);
  });

  it("drops filler words and adds looser variants for long queries", () => {
    const q = parseQuery("Pokémon TCG Scarlet & Violet Prismatic Evolutions Booster Bundle");
    expect(q.category).toBe("Booster Bundle");
    expect(q.core).toBe("scarlet violet prismatic evolutions");
    expect(q.variants).toContain("scarlet violet");
    expect(q.variants).toContain("prismatic evolutions");
  });

  it("keeps a bare product type as the query", () => {
    const q = parseQuery("upc");
    expect(q.variants).toEqual(["ultra premium collection"]);
  });
});

describe("rankByQuery", () => {
  it("puts the matching product type and words first", () => {
    const q = parseQuery("prismatic evolutions etb");
    const ranked = rankByQuery(
      [p("Prismatic Evolutions Booster Bundle", "Prismatic Evolutions"), p("Prismatic Evolutions Elite Trainer Box", "Prismatic Evolutions"), p("Umbreon ex", "Prismatic Evolutions", "single")],
      q,
    );
    expect(ranked[0].product.name).toBe("Prismatic Evolutions Elite Trainer Box");
  });

  it("prefers the named set over the product type", () => {
    const q = parseQuery("evolving skies etb");
    const ranked = rankByQuery([p("Crown Zenith Elite Trainer Box", "Crown Zenith"), p("Evolving Skies Booster Box", "Evolving Skies"), p("Evolving Skies Elite Trainer Box", "Evolving Skies")], q);
    expect(ranked.map((r) => r.product.name)).toEqual(["Evolving Skies Elite Trainer Box", "Evolving Skies Booster Box", "Crown Zenith Elite Trainer Box"]);
  });
});
