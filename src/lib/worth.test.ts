import { describe, expect, it } from "vitest";
import type { EbaySales } from "./ebay-types";
import { BLEND_FACTOR, companyAdjusted } from "./graded";
import { gradedLookup, gradedPrice, gradedSourceLabel, gradedWorth, gradesFor, GRADED_ROWS, isEstimate, lookupGrades, psaIfGraded, rawWorth, rowGradeTitle } from "./worth";

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
    // CGC: Pristine 10 above its 10 (a Gem Mint 10).
    expect(lookupGrades("CGC")).toEqual(["Pristine 10", "10", "9.5", "9", "8.5", "8", "7.5", "7", "6", "5"]);
  });

  it("lists one named company on every table row", () => {
    expect(GRADED_ROWS.map((r) => `${r.company} ${rowGradeTitle(r)}`)).toEqual(["PSA 10", "BGS 10", "CGC Pristine 10", "CGC Gem Mint 10", "SGC 10", "BGS 9.5", "PSA 9", "PSA 8", "PSA 7"]);
  });

  it("scales PriceCharting's any-company price to a company", () => {
    expect(BLEND_FACTOR).toBe(0.9);
    expect(companyAdjusted(180, "PSA")).toBe(200);
    expect(companyAdjusted(180, "bgs")).toBe(210);
    expect(companyAdjusted(100, "CGC")).toBe(80);
    expect(companyAdjusted(100, "XYZ")).toBe(77.78);
  });

  it("prices a slab: eBay median, then PriceCharting (adjusted below 10), then the last sale, then the curve", () => {
    const pc = { ungraded: 100, grades: { "PSA 10": 700, "9": 180, "9.5": 300 }, updatedAt: "2026-10-30" };
    const e = ebay({ graded: { "PSA 10": { median: 600, count: 2, lastPrice: 610, lastSold: null }, "CGC 9": { median: 150, count: 1, lastPrice: 140, lastSold: null } } });
    expect(gradedPrice("p", { company: "PSA", grade: "10" }, pc, e, 100)).toEqual({ value: 600, source: { kind: "ebay", count: 2 } });
    expect(gradedPrice("p", { company: "PSA", grade: "10" }, pc, null, 100)).toEqual({ value: 700, source: { kind: "guide" } });
    // One sale isn't enough: PriceCharting's 9, scaled to CGC, wins.
    expect(gradedPrice("p", { company: "CGC", grade: "9" }, pc, e, 100)).toEqual({ value: 144, source: { kind: "adjusted" } });
    expect(gradedPrice("p", { company: "BGS", grade: "9.5" }, pc, null, 100)).toEqual({ value: 350, source: { kind: "adjusted" } });
    expect(gradedPrice("p", { company: "CGC", grade: "9" }, null, e, 100)).toEqual({ value: 140, source: { kind: "ebay", count: 1 } });
    expect(gradedPrice("p", { company: "TAG", grade: "6" }, pc, e, 100)?.source).toEqual({ kind: "curve" });
    expect(gradedPrice("p", { company: "TAG", grade: "6" }, null, null, null)).toBeNull();
    expect(isEstimate({ kind: "adjusted" })).toBe(true);
    expect(isEstimate({ kind: "curve" })).toBe(true);
    expect(isEstimate({ kind: "guide" })).toBe(false);
    expect(gradedSourceLabel({ kind: "ebay", count: 3 })).toBe("eBay");
    expect(gradedSourceLabel({ kind: "guide" })).toBe("PriceCharting");
    expect(gradedSourceLabel({ kind: "curve" })).toBe("estimate");
  });

  it("looks up a grade with the app's detail strings", () => {
    const pc = { ungraded: 100, grades: { "PSA 10": 700, "9": 180 }, updatedAt: "2026-10-30" };
    const e = ebay({ graded: { "PSA 10": { median: 600, count: 4, lastPrice: 610, lastSold: null }, "CGC 9": { median: 150, count: 1, lastPrice: 140, lastSold: null } } });
    expect(gradedLookup("p", 100, { company: "PSA", grade: "10" }, e, pc)).toMatchObject({ price: 600, detail: "Median of 4 PSA 10 eBay sales this month" });
    expect(gradedLookup("p", 100, { company: "PSA", grade: "10" }, null, pc)).toMatchObject({ price: 700, detail: "PriceCharting · PSA 10" });
    expect(gradedLookup("p", 100, { company: "CGC", grade: "9" }, e, pc)).toMatchObject({ price: 144, detail: "Estimate · PriceCharting's grade 9 price for any company, adjusted for CGC" });
    expect(gradedLookup("p", 100, { company: "CGC", grade: "9" }, e, null)).toMatchObject({ price: 140, detail: "Last CGC 9 eBay sale" });
    expect(gradedLookup("p", 100, { company: "TAG", grade: "6" }, e, pc).detail).toBe("Estimate from the usual grade curve");
    expect(gradedLookup("p", null, { company: "TAG", grade: "6" }, null, null)).toEqual({ price: null, source: null, detail: "No sales or price guide for this grade yet" });
  });

  it("prices a raw card as a PSA 10 or 9: PriceCharting (9 adjusted, ≈), else the curve", () => {
    const pc = { ungraded: 100, grades: { "PSA 10": 640, "9": 180 }, updatedAt: "" };
    expect(psaIfGraded("p", 100, "10", pc)).toEqual({ price: 640, estimate: false });
    expect(psaIfGraded("p", 100, "9", pc)).toEqual({ price: 200, estimate: true });
    expect(psaIfGraded("p", 100, "9", { ungraded: 100, grades: { "PSA 10": 640 }, updatedAt: "" }).estimate).toBe(true);
  });
});
