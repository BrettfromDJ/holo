import { describe, expect, it } from "vitest";
import { daysBefore, withOwnChanges, type PriceDay } from "./price-days";

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
