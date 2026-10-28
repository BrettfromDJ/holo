import { describe, expect, it } from "vitest";
import { concentration, drawdownSeries, monthlyReturns, riskStats } from "./analytics";
import type { HoldingView, TimelinePoint } from "./portfolio";

function pt(date: string, twrIndex: number, marketGain = 0, dailyReturn = 0): TimelinePoint {
  return { date, value: 100 * twrIndex, costBasis: 100, costBasisPriced: 100, unrealized: 0, marketGain, dailyReturn, twrIndex, cumulativeMarketGain: 0, invested: 0, proceeds: 0, unpricedHoldings: 0 };
}

describe("analytics", () => {
  const series = [pt("2026-01-30", 1), pt("2026-01-31", 1.2, 20, 0.2), pt("2026-02-01", 0.9, -30, -0.25), pt("2026-02-28", 1.08, 18, 0.2)];

  it("finds the max drawdown and current drawdown", () => {
    const r = riskStats(series);
    expect(r.maxDrawdown).toBeCloseTo(0.9 / 1.2 - 1);
    expect(r.maxDrawdownFrom).toBe("2026-01-31");
    expect(r.maxDrawdownTo).toBe("2026-02-01");
    expect(r.currentDrawdown).toBeCloseTo(1.08 / 1.2 - 1);
    expect(r.totalReturn).toBeCloseTo(0.08);
    expect(r.bestDay?.gain).toBe(20);
    expect(r.worstDay?.gain).toBe(-30);
  });

  it("chains monthly returns from month-end to month-end", () => {
    const m = monthlyReturns(series);
    expect(m).toHaveLength(2);
    expect(m[0]).toMatchObject({ year: 2026, month: 0 });
    expect(m[0].ret).toBeCloseTo(0.2);
    expect(m[1].ret).toBeCloseTo(1.08 / 1.2 - 1);
    expect(m[1].gain).toBeCloseTo(-12);
  });

  it("builds an underwater series", () => {
    expect(drawdownSeries(series).map((d) => Math.round(d.drawdown * 100))).toEqual([0, 0, -25, -10]);
  });

  it("measures concentration", () => {
    const h = (value: number) => ({ value }) as HoldingView;
    const c = concentration([h(50), h(25), h(25)]);
    expect(c.top1).toBeCloseTo(0.5);
    expect(c.effective).toBeCloseTo(1 / (0.25 + 0.0625 * 2));
  });
});
