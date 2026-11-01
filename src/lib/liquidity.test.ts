import { describe, expect, it } from "vitest";
import type { EbaySale, EbaySales, EbayStats } from "./ebay-types";
import { quantile, sellSpeed, sellSpeedTier } from "./liquidity";

// Same inputs and expected outputs as the app's LiquidityTests.swift.
const TODAY = "2026-11-01";

const sale = (price: number, soldDate: string, grade: string | null = null, listPrice: number | null = null): EbaySale => ({
  soldDate,
  price,
  bestOffer: listPrice !== null,
  listPrice,
  grade,
  condition: null,
  title: "",
  url: "",
});

const stats = (count: number, lastSold: string | null): EbayStats => ({ median: null, count, lastPrice: null, lastSold });

const ebay = (ungraded: EbayStats, sales: EbaySale[], graded: Record<string, EbayStats> = {}): EbaySales => ({ printing: null, ungraded, graded, sales, asOf: TODAY, days: 30 });

/** 30 sold, ten sales within a few dollars of each other, the latest today. */
const busy = () => ebay(stats(30, "2026-11-01"), [100, 102, 98, 101, 99, 100, 103, 97, 100, 101].map((p, i) => sale(p, i === 0 ? "2026-11-01" : "2026-10-25")));

describe("sells fast", () => {
  it("quantiles interpolate between prices", () => {
    expect(quantile([10, 20, 30, 40], 0.5)).toBe(25);
    expect(quantile([10, 20, 30, 40], 0.25)).toBe(17.5);
    expect(quantile([10, 20, 30, 40], 0.75)).toBe(32.5);
  });

  it("a busy card with tight prices sells fast", () => {
    expect(sellSpeed(busy(), null, TODAY)).toEqual({ score: 99, tier: "Sells fast", segments: 3, sold: 30 });
  });

  it("a medium card sells steady", () => {
    const e = ebay(stats(6, "2026-10-22"), [sale(80, "2026-10-22"), sale(100, "2026-10-18"), sale(90, "2026-10-15"), sale(110, "2026-10-12"), sale(95, "2026-10-08", null, 120), sale(105, "2026-10-04")]);
    expect(sellSpeed(e, null, TODAY)).toEqual({ score: 66, tier: "Sells steady", segments: 2, sold: 6 });
  });

  it("a rare card with scattered prices is slow to sell", () => {
    const e = ebay(stats(2, "2026-10-07"), [sale(40, "2026-10-07"), sale(90, "2026-10-03", null, 120)]);
    expect(sellSpeed(e, null, TODAY)).toEqual({ score: 36, tier: "Slow to sell", segments: 1, sold: 2 });
  });

  it("returns nothing without enough sales", () => {
    expect(sellSpeed(ebay(stats(1, "2026-10-30"), [sale(50, "2026-10-30")]), null, TODAY)).toBeNull();
    expect(sellSpeed(ebay(stats(0, null), []), null, TODAY)).toBeNull();
    expect(sellSpeed(null, null, TODAY)).toBeNull();
    // A grade that never sold.
    expect(sellSpeed(busy(), "PSA 10", TODAY)).toBeNull();
  });

  it("a grade uses only its own stats and sales", () => {
    const base = busy();
    const e: EbaySales = {
      ...base,
      graded: { "PSA 10": stats(3, "2026-10-21") },
      sales: [...base.sales, sale(500, "2026-10-21", "PSA 10"), sale(650, "2026-10-14", "PSA 10"), sale(420, "2026-10-06", "PSA 10"), sale(900, "2026-10-28", "PSA 9")],
    };
    expect(sellSpeed(e, "PSA 10", TODAY)).toEqual({ score: 55, tier: "Sells steady", segments: 2, sold: 3 });
    // Ungraded is unchanged by the slab sales.
    expect(sellSpeed(e, null, TODAY)?.score).toBe(99);
  });

  it("buyers talking the price down lowers the score", () => {
    const e = busy();
    // Half the sales were best offers well under the asking price; one was within 5% (doesn't count).
    e.sales = e.sales.map((s, i) => (i < 5 ? { ...s, bestOffer: true, listPrice: s.price * 1.25 } : i === 5 ? { ...s, bestOffer: true, listPrice: s.price * 1.02 } : s));
    expect(sellSpeed(e, null, TODAY)).toEqual({ score: 94, tier: "Sells fast", segments: 3, sold: 30 });
  });

  it("tiers split at 70 and 40", () => {
    expect(sellSpeedTier(70)).toBe("Sells fast");
    expect(sellSpeedTier(69)).toBe("Sells steady");
    expect(sellSpeedTier(40)).toBe("Sells steady");
    expect(sellSpeedTier(39)).toBe("Slow to sell");
  });
});
