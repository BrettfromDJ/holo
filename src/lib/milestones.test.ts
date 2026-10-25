import { describe, expect, it } from "vitest";
import type { HoldingView, PortfolioSummary } from "./finance/portfolio";
import { pickNew, reachedMilestones } from "./milestones";

const summary = (marketValue: number, unitCount = 3) => ({ marketValue, unitCount }) as PortfolioSummary;
const holding = (key: string, pct: number) =>
  ({ key, unrealizedPct: pct, costBasis: 100, value: 100 * (1 + pct), identity: { grade: null }, product: { name: "Umbreon VMAX (Alt Art)" } }) as unknown as HoldingView;

describe("milestones", () => {
  it("reaches every value step below the total", () => {
    const ids = reachedMilestones(summary(12_000), []).map((m) => m.id);
    expect(ids).toContain("value:10000");
    expect(ids).toContain("value:500");
    expect(ids).not.toContain("value:25000");
  });

  it("shows only the highest new step per kind", () => {
    const reached = reachedMilestones(summary(12_000), [holding("tcgapi:1|Holofoil|Near Mint|", 2.2)]);
    const { show, record } = pickNew(reached, new Set(), false);
    expect(show.map((m) => m.id)).toEqual(["value:10000", "gain:tcgapi:1|Holofoil|Near Mint|:2"]);
    expect(record.length).toBe(reached.length);
  });

  it("shows a single milestone on the first run and nothing already seen", () => {
    const reached = reachedMilestones(summary(1_200), [holding("a", 1.1)]);
    expect(pickNew(reached, new Set(), true).show).toHaveLength(1);
    const seen = new Set(reached.map((m) => m.id));
    expect(pickNew(reached, seen, false).show).toHaveLength(0);
  });
});
