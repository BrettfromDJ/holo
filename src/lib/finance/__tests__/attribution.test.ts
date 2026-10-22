import { describe, expect, it } from "vitest";
import { buildDemoData } from "../../demo/dataset";
import { attributeGains } from "../attribution";
import { computeHoldings, summarize, totalRealized } from "../portfolio";

describe("attributeGains", () => {
  const today = "2026-10-22";
  const data = buildDemoData(today);
  const holdings = computeHoldings(data, today);
  const realized = totalRealized(data, today);
  const summary = summarize(holdings, realized.total);

  it("unrealized steps sum exactly to the portfolio's unrealized gain", () => {
    const a = attributeGains(holdings, realized.entries, data.products, { mode: "unrealized", group: "product" });
    expect(a.total).toBeCloseTo(summary.unrealized, 6);
    expect(a.steps[a.steps.length - 1].end).toBeCloseTo(summary.unrealized, 6);
    expect(a.steps[0].start).toBe(0);
  });

  it("realized and all-time modes reconcile with the totals", () => {
    const r = attributeGains(holdings, realized.entries, data.products, { mode: "realized", group: "product" });
    expect(r.total).toBeCloseTo(realized.total, 6);
    const all = attributeGains(holdings, realized.entries, data.products, { mode: "all", group: "set" });
    expect(all.total).toBeCloseTo(summary.unrealized + realized.total, 6);
  });

  it("orders gains before losses and folds the tail into Other without changing the total", () => {
    const full = attributeGains(holdings, realized.entries, data.products, { mode: "unrealized", group: "product" });
    const capped = attributeGains(holdings, realized.entries, data.products, { mode: "unrealized", group: "product", maxRows: 5 });
    expect(capped.steps).toHaveLength(5);
    expect(capped.steps[4].key).toBe("__other");
    expect(capped.steps[4].end).toBeCloseTo(full.total, 6);
    const biggestLoss = full.steps.filter((s) => s.gain < 0).sort((a, b) => a.gain - b.gain)[0];
    expect(capped.steps.some((s) => s.key === biggestLoss.key)).toBe(true);
    const signs = full.steps.map((s) => Math.sign(s.gain));
    expect(signs.indexOf(-1)).toBeGreaterThan(signs.lastIndexOf(1));
  });
});
