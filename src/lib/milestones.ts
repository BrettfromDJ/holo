import type { HoldingView, PortfolioSummary } from "./finance/portfolio";
import { money } from "./format";

export interface Milestone {
  /** Stable id; each milestone is celebrated once. */
  id: string;
  title: string;
  description?: string;
  /** Higher ranks are shown first when several are new at once. */
  rank: number;
}

const VALUE_STEPS = [500, 1_000, 2_500, 5_000, 10_000, 25_000, 50_000, 100_000, 250_000, 500_000, 1_000_000];
const ITEM_STEPS = [10, 25, 50, 100, 250, 500, 1_000];
/** Gain ratios worth celebrating on a single holding, with how to say them. */
const GAIN_STEPS: [ratio: number, phrase: string][] = [
  [1, "has doubled since you bought it"],
  [2, "has tripled since you bought it"],
  [4, "is up 5× since you bought it"],
  [9, "is up 10× since you bought it"],
];

function shortName(name: string) {
  return name.replace(/\s*\(.*?\)\s*/g, " ").trim();
}

/** Every milestone the collection has reached right now. */
export function reachedMilestones(summary: PortfolioSummary, holdings: HoldingView[]): Milestone[] {
  const out: Milestone[] = [];
  VALUE_STEPS.forEach((step, i) => {
    if (summary.marketValue >= step) {
      out.push({ id: `value:${step}`, title: `Your collection just passed ${money(step).replace(/\.00$/, "")}`, description: `Now worth ${money(summary.marketValue)}.`, rank: 100 + i });
    }
  });
  ITEM_STEPS.forEach((step, i) => {
    if (summary.unitCount >= step) out.push({ id: `items:${step}`, title: `${step} items in your collection`, rank: 50 + i });
  });
  for (const h of holdings) {
    if (h.unrealizedPct === null || !h.product || h.identity.grade) continue;
    GAIN_STEPS.forEach(([ratio, phrase], i) => {
      if (h.unrealizedPct! >= ratio) {
        out.push({
          id: `gain:${h.key}:${ratio}`,
          title: `${shortName(h.product!.name)} ${phrase}`,
          description: `Paid ${money(h.costBasis)} · worth ${money(h.value)}`,
          rank: 80 + i,
        });
      }
    });
  }
  return out;
}

/**
 * Split reached milestones into the ones to show now and the ones to record
 * silently. On the very first run only the single best one is shown, so a
 * long-standing collection isn't greeted by a flood.
 */
export function pickNew(reached: Milestone[], seen: Set<string>, firstRun: boolean, max = 2): { show: Milestone[]; record: string[] } {
  const fresh = reached.filter((m) => !seen.has(m.id)).sort((a, b) => b.rank - a.rank);
  // Only the highest step of each kind is worth saying (passing $10k implies $5k).
  const bestPerKind = new Map<string, Milestone>();
  for (const m of fresh) {
    const kind = m.id.startsWith("gain:") ? m.id.slice(0, m.id.lastIndexOf(":")) : m.id.split(":")[0];
    if (!bestPerKind.has(kind)) bestPerKind.set(kind, m);
  }
  const candidates = [...bestPerKind.values()].sort((a, b) => b.rank - a.rank);
  return { show: candidates.slice(0, firstRun ? 1 : max), record: fresh.map((m) => m.id) };
}
