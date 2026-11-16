import { describe, expect, it } from "vitest";
import { backedBySales, daysBefore, moveHeld, withOwnChanges, type PriceDay } from "./price-days";

const row = (market: number | null, c24: number | null = null, c7: number | null = null) => ({ product_id: "p", printing: "Holofoil", market_price: market, change_24h_pct: c24, change_7d_pct: c7 });
const day = (d: string, market: number): PriceDay => ({ product_id: "p", printing: "Holofoil", day: d, market });

describe("withOwnChanges", () => {
  const today = "2026-11-16";
  it("works out 24-hour and 7-day changes from our daily prices", () => {
    const [r] = withOwnChanges([row(120)], [day("2026-11-15", 100), day("2026-11-09", 80)], today);
    expect(r.change_24h_pct).toBe(20);
    expect(r.change_7d_pct).toBe(50);
  });
  it("uses a day either side when the exact day is missing", () => {
    const [r] = withOwnChanges([row(90)], [day("2026-11-14", 100), day("2026-11-08", 100)], today);
    expect(r.change_24h_pct).toBe(-10);
    expect(r.change_7d_pct).toBe(-10);
  });
  it("keeps changes TCG API sent, and leaves cards without history or a price alone", () => {
    expect(withOwnChanges([row(120, 5, 6)], [day("2026-11-15", 100), day("2026-11-09", 80)], today)[0]).toMatchObject({ change_24h_pct: 5, change_7d_pct: 6 });
    expect(withOwnChanges([row(120)], [], today)[0]).toMatchObject({ change_24h_pct: null, change_7d_pct: null });
    expect(withOwnChanges([row(null)], [day("2026-11-15", 100)], today)[0]).toMatchObject({ change_24h_pct: null });
  });
  it("counts days back across months", () => {
    expect(daysBefore("2026-12-03", 7)).toBe("2026-11-26");
  });
});

describe("moveHeld", () => {
  const today = "2026-11-16";
  const d = (day: string, market: number) => ({ product_id: "p", printing: "", day, market });
  it("counts a weekly rise only when yesterday was already up on the week", () => {
    expect(moveHeld([d("2026-11-15", 120), d("2026-11-09", 100)], today, "up")).toBe(true);
    expect(moveHeld([d("2026-11-15", 98), d("2026-11-09", 100)], today, "up")).toBe(false);
    expect(moveHeld([d("2026-11-15", 90), d("2026-11-09", 100)], today, "down")).toBe(true);
  });
  it("can't judge without the days, so lets it through", () => {
    expect(moveHeld([], today, "up")).toBe(true);
  });
});

describe("backedBySales", () => {
  it("trusts a price near eBay's median, not one far off it", () => {
    expect(backedBySales(110, { median: 100, count: 5 })).toBe(true);
    expect(backedBySales(190, { median: 100, count: 5 })).toBe(false);
    expect(backedBySales(50, { median: 100, count: 5 })).toBe(false);
  });
  it("trusts it when there aren't enough sales to judge", () => {
    expect(backedBySales(190, { median: 100, count: 2 })).toBe(true);
    expect(backedBySales(190, null)).toBe(true);
  });
});
