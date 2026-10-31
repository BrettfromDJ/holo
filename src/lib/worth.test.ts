import { describe, expect, it } from "vitest";
import type { EbaySales } from "./ebay-types";
import { estimatedGradedTable, gradedLookup, gradedWorth, gradesFor, GRADED_ROWS, lookupGrades, psaIfGraded, rawWorth } from "./worth";

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

  it("lists grades 10 down to 5 for the lookup", () => {
    expect(lookupGrades("PSA")).toEqual(["10", "9", "8", "7", "6", "5"]);
    expect(lookupGrades("BGS")).toEqual(["10", "9.5", "9", "8.5", "8", "7.5", "7", "6", "5"]);
  });

  it("looks up a grade: eBay median, then PriceCharting, then the last sale, then the curve", () => {
    const pc = { ungraded: 100, grades: { "PSA 10": 700, "9": 180 }, updatedAt: "2026-10-30" };
    const e = ebay({ graded: { "PSA 10": { median: 600, count: 4, lastPrice: 610, lastSold: null }, "CGC 9": { median: 150, count: 1, lastPrice: 140, lastSold: null } } });
    expect(gradedLookup("p", 100, { company: "PSA", grade: "10" }, e, pc)).toMatchObject({ price: 600, source: "sales" });
    expect(gradedLookup("p", 100, { company: "PSA", grade: "10" }, null, pc)).toMatchObject({ price: 700, source: "guide", detail: "PriceCharting · PSA 10" });
    // Lower grades are for any company, so a CGC 9 uses PriceCharting's 9 over a single sale.
    expect(gradedLookup("p", 100, { company: "CGC", grade: "9" }, e, pc)).toMatchObject({ price: 180, detail: "PriceCharting · grade 9, any grading company" });
    expect(gradedLookup("p", 100, { company: "CGC", grade: "9" }, e, null)).toMatchObject({ price: 140, detail: "Last CGC 9 eBay sale" });
    expect(gradedLookup("p", 100, { company: "TAG", grade: "6" }, e, pc).source).toBe("estimate");
    expect(gradedLookup("p", null, { company: "TAG", grade: "6" }, null, null).price).toBeNull();
  });

  it("estimates the whole table from the grade curve", () => {
    const t = estimatedGradedTable("p", 100)!;
    expect(t.ungraded).toBe(100);
    expect(Object.keys(t.grades).sort()).toEqual(GRADED_ROWS.map((r) => r.key).sort());
    expect(t.grades["PSA 10"]).toBeGreaterThan(t.grades["9"]);
    expect(estimatedGradedTable("p", null)).toBeNull();
  });

  it("prices a raw card as a PSA 10 or 9 from PriceCharting, else the curve", () => {
    expect(psaIfGraded("p", 100, "10", { ungraded: 100, grades: { "PSA 10": 640 }, updatedAt: "" })).toEqual({ price: 640, estimate: false });
    expect(psaIfGraded("p", 100, "9", { ungraded: 100, grades: { "PSA 10": 640 }, updatedAt: "" }).estimate).toBe(true);
  });
});
