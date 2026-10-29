import { describe, expect, it } from "vitest";
import { sampleEbaySales } from "./ebay-sample";

describe("sample eBay sales", () => {
  const today = "2026-10-29";

  it("is the same on every visit", () => {
    expect(sampleEbaySales("p1", "Mew ex", "Holofoil", 30, today)).toEqual(sampleEbaySales("p1", "Mew ex", "Holofoil", 30, today));
  });

  it("keeps ungraded sales near market and inside the 30-day window", () => {
    const e = sampleEbaySales("p2", "Umbreon VMAX", "Holofoil", 1000, today)!;
    expect(e.ungraded.count).toBeGreaterThanOrEqual(3);
    expect(e.ungraded.median!).toBeGreaterThan(600);
    expect(e.ungraded.median!).toBeLessThan(1200);
    for (const s of e.sales) expect(s.soldDate >= "2026-09-30" && s.soldDate <= today).toBe(true);
    expect(e.sales.map((s) => s.soldDate)).toEqual([...e.sales.map((s) => s.soldDate)].sort().reverse());
  });

  it("prices PSA 10 sales above ungraded", () => {
    const e = sampleEbaySales("p3", "Charizard", null, 200, today)!;
    if (e.graded["PSA 10"]) expect(e.graded["PSA 10"].median!).toBeGreaterThan(e.ungraded.median!);
  });

  it("has nothing without a market price", () => {
    expect(sampleEbaySales("p4", "Unknown", null, null, today)).toBeNull();
  });
});
