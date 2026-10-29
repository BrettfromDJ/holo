import { describe, expect, it } from "vitest";
import type { EbaySales } from "./ebay-types";
import { gradedWorth, gradesFor, rawWorth } from "./worth";

const ebay = (over: Partial<EbaySales> = {}): EbaySales => ({ printing: null, ungraded: { median: 100, count: 5, lastPrice: 100, lastSold: null }, graded: {}, sales: [], asOf: "2026-10-29", days: 30, ...over });
const sale = (price: number, condition: string | null, grade: string | null = null) => ({ soldDate: "2026-10-20", price, bestOffer: false, listPrice: null, grade, condition, title: "", url: "" });

describe("what's it worth", () => {
  it("uses market for Near Mint and labels other conditions as estimates", () => {
    expect(rawWorth(100, "NM", null)).toMatchObject({ price: 100, source: "market" });
    expect(rawWorth(100, "LP", null)).toMatchObject({ price: 85, source: "estimate", detail: "Estimated at 85% of Near Mint" });
    expect(rawWorth(100, "DMG", null).price).toBe(35);
  });

  it("uses TCGplayer's price for a condition first", () => {
    const rows = [{ printing: "Holofoil", condition: "Lightly Played", price: 91.5, basis: "median" as const, samples: 6, updatedAt: null }];
    expect(rawWorth(100, "LP", null, rows, "Holofoil")).toMatchObject({ price: 91.5, source: "market", detail: "TCGplayer Lightly Played listings · median of 6" });
    expect(rawWorth(100, "MP", null, rows, "Holofoil").source).toBe("estimate");
  });

  it("prefers real condition sales when there are enough", () => {
    const e = ebay({ sales: [sale(70, "Lightly Played"), sale(80, "Lightly Played"), sale(90, "Lightly Played")] });
    expect(rawWorth(100, "LP", e)).toMatchObject({ price: 80, source: "sales", sold: 3 });
  });

  it("uses graded sales, then the guide, then the curve", () => {
    const e = ebay({ graded: { "PSA 10": { median: 600, count: 4, lastPrice: 610, lastSold: null } } });
    expect(gradedWorth("p", 100, { company: "PSA", grade: "10" }, e)).toMatchObject({ price: 600, source: "sales" });
    expect(gradedWorth("p", 100, { company: "PSA", grade: "9" }, e, null, true).source).toBe("guide");
    expect(gradedWorth("p", 100, { company: "PSA", grade: "9" }, e, 222).price).toBe(222);
    // Without a connected guide, a real card's curve value is an estimate.
    expect(gradedWorth("p", 100, { company: "PSA", grade: "9" }, e).source).toBe("estimate");
    expect(gradedWorth("p", 100, { company: "PSA", grade: "3" }, e).source).toBe("estimate");
  });

  it("gives half grades only where companies use them", () => {
    expect(gradesFor("PSA")).not.toContain("9.5");
    expect(gradesFor("BGS")).toContain("9.5");
  });
});
