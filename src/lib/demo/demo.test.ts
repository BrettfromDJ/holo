import { describe, expect, it } from "vitest";
import { computeHoldings, computeTimeline, performanceOf, slicePoints, summarize, totalRealized } from "../finance/portfolio";
import { withSampleGradedPrices } from "../graded";
import { buildDemoData } from "./dataset";

describe("sample dataset", () => {
  const today = "2026-10-22";
  const data = buildDemoData(today);

  it("is clearly namespaced as sample data", () => {
    expect(Object.keys(data.products).every((id) => id.startsWith("sample:"))).toBe(true);
    expect(Object.values(data.prices).every((p) => p.source === "sample")).toBe(true);
  });

  it("produces a coherent portfolio", () => {
    // As in the app: graded slabs are priced from the (sample) graded source.
    const data = withSampleGradedPrices(buildDemoData(today), today);
    const holdings = computeHoldings(data, today);
    const s = summarize(holdings, totalRealized(data, today).total);
    const tl = computeTimeline(data, today);
    const last = tl[tl.length - 1];
    expect(Math.abs(last.value - s.marketValue)).toBeLessThan(0.01);
    expect(Math.abs(last.costBasis - s.costBasis)).toBeLessThan(0.01);
    expect(s.unpricedCount).toBe(0);
    expect(holdings.length).toBeGreaterThan(10);
    const perf = performanceOf(slicePoints(tl, "1Y", today))!;
    expect(Number.isFinite(perf.twr)).toBe(true);
  });
});
