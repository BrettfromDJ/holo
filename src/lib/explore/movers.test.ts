import { describe, expect, it } from "vitest";
import type { Product } from "../types";
import { eraOf, isBoosterBox, isCodeCard, pickBoosterBoxes, pickMovers, type MoverPriceRow } from "./movers";

function product(id: string, name: string, extra: Partial<Product> = {}): Product {
  return {
    id,
    source: "tcgapi",
    externalId: id,
    name,
    setName: "Set",
    setId: "set",
    number: null,
    rarity: null,
    productType: null,
    kind: "single",
    imageUrl: null,
    tcgplayerId: null,
    tcgplayerUrl: null,
    ...extra,
  };
}

function price(id: string, market: number | string | null, change7: number | string | null, extra: Partial<MoverPriceRow> = {}): MoverPriceRow {
  return { product_id: id, printing: "Holofoil", market_price: market, change_7d_pct: change7, change_30d_pct: null, source_updated_at: null, ...extra };
}

describe("isCodeCard", () => {
  it("spots code cards by name, type or rarity", () => {
    expect(isCodeCard(product("a", "Code Card - Surging Sparks Booster Pack"))).toBe(true);
    expect(isCodeCard(product("a", "Something", { rarity: "Code Card" }))).toBe(true);
    expect(isCodeCard(product("a", "Pikachu ex"))).toBe(false);
  });
});

describe("isBoosterBox", () => {
  it("keeps booster boxes and displays, not bundles or singles", () => {
    expect(isBoosterBox(product("a", "Evolving Skies Booster Box", { kind: "sealed" }))).toBe(true);
    expect(isBoosterBox(product("a", "OP-05 Booster Display", { kind: "sealed" }))).toBe(true);
    expect(isBoosterBox(product("a", "Prismatic Evolutions Booster Bundle", { kind: "sealed" }))).toBe(false);
    expect(isBoosterBox(product("a", "151 Elite Trainer Box", { kind: "sealed" }))).toBe(false);
    expect(isBoosterBox(product("a", "Booster Box Promo", { kind: "single" }))).toBe(false);
  });
});

describe("pickMovers", () => {
  const products = new Map<string, Product>([
    ["a", product("a", "Umbreon VMAX")],
    ["b", product("b", "Charizard ex")],
    ["c", product("c", "Pikachu")],
    ["box", product("box", "Evolving Skies Booster Box", { kind: "sealed" })],
    ["code", product("code", "Code Card - 151 Booster Pack")],
  ]);

  it("ranks singles by 7-day rise, skipping cheap, sealed, code cards and missing changes", () => {
    const rows = [
      price("box", 900, 40),
      price("code", 10, 35),
      price("c", 2, 30), // under $5
      price("b", "50", "12.5"),
      price("a", 300, 20),
      price("a", 120, 18, { printing: "Reverse Holofoil" }), // second printing: skipped
      price("missing", 20, 50), // product not loaded
    ];
    const up = pickMovers(rows, products, "up");
    expect(up.map((m) => m.product.id)).toEqual(["a", "b"]);
    expect(up[0]).toMatchObject({ market: 300, change7dPct: 20, printing: "Holofoil" });
    expect(up[1]).toMatchObject({ market: 50, change7dPct: 12.5 });
  });

  it("ranks today's movers by the 24-hour change with by: 24h", () => {
    const rows = [price("a", 300, 20, { change_24h_pct: 3 }), price("b", 50, 1, { change_24h_pct: 9 }), price("c", 40, 50, { change_24h_pct: null })];
    const today = pickMovers(rows, products, "up", { by: "24h", minPrice: 10 });
    expect(today.map((m) => m.product.id)).toEqual(["b", "a"]);
    expect(today[0]).toMatchObject({ change24hPct: 9, change7dPct: 1 });
  });

  it("picks hot sealed with kind: sealed only, above the sealed floor", () => {
    const rows = [price("box", 900, 40), price("a", 300, 20), price("code", 10, 35)];
    expect(pickMovers(rows, products, "up", { kind: "sealed", minPrice: 20 }).map((m) => m.product.id)).toEqual(["box"]);
  });

  it("ranks falls, ignoring rises and flat or unknown changes", () => {
    const rows = [price("a", 300, -4), price("b", 50, -25), price("c", 10, 0), price("c", 10, null)];
    expect(pickMovers(rows, products, "down").map((m) => m.product.id)).toEqual(["b", "a"]);
    expect(pickMovers(rows, products, "up")).toEqual([]);
  });

  it("caps the list and names the brand", () => {
    const many = new Map<string, Product>();
    const rows: MoverPriceRow[] = [];
    for (let i = 0; i < 20; i++) {
      many.set(`p${i}`, product(`p${i}`, `Card ${i}`));
      rows.push(price(`p${i}`, 10, 100 - i));
    }
    const up = pickMovers(rows, many, "up", { gameName: () => "Pokemon" });
    expect(up).toHaveLength(12);
    expect(up[0].gameName).toBe("Pokemon");
  });
});

describe("pickBoosterBoxes", () => {
  it("lists priced booster boxes, most valuable first, capped", () => {
    const products = [
      product("es", "Evolving Skies Booster Box", { kind: "sealed" }),
      product("op", "Romance Dawn Booster Display", { kind: "sealed" }),
      product("etb", "151 Elite Trainer Box", { kind: "sealed" }),
      product("unpriced", "Lost Origin Booster Box", { kind: "sealed" }),
    ];
    const rows = [
      price("es", 1180, 2, { change_30d_pct: 8 }),
      price("op", null, null, { printing: "" }),
      price("op", 420, -3, { printing: "Normal", change_30d_pct: "-6.5" }),
      price("etb", 600, 1),
      price("unpriced", null, null),
    ];
    const boxes = pickBoosterBoxes(products, rows);
    expect(boxes.map((b) => b.product.id)).toEqual(["es", "op"]);
    expect(boxes[1]).toMatchObject({ market: 420, printing: "Normal", change30dPct: -6.5, change7dPct: -3 });
    expect(pickBoosterBoxes(products, rows, { limit: 1 })).toHaveLength(1);
  });
});

describe("eraOf", () => {
  it("splits sets into vintage, mid-era and modern by release date", () => {
    expect(eraOf("1999-01-09")).toBe("vintage"); // Base Set
    expect(eraOf("2003-07-01")).toBe("vintage"); // EX Ruby & Sapphire
    expect(eraOf("2007-02-14")).toBe("vintage"); // EX Power Keepers
    expect(eraOf("2007-05-23")).toBe("midEra"); // Diamond & Pearl
    expect(eraOf("2016-11-02")).toBe("midEra"); // Evolutions (XY)
    expect(eraOf("2017-02-03")).toBe("modern"); // Sun & Moon
    expect(eraOf("2020-02-07")).toBe("modern"); // Sword & Shield
    expect(eraOf(null)).toBeNull();
  });
});
