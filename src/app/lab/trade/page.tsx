"use client";

import { useMemo, useState } from "react";
import { PageHeader } from "@/components/shell/page-header";
import { Segmented } from "@/components/ui/segmented";
import { VerdictFix, VerdictGauge, VerdictGrade, VerdictLedger, VerdictMeter, VerdictNet, VerdictPiles, VerdictPlans, VerdictPull, VerdictSwap, VerdictTug, VerdictVersus, type VerdictItem } from "@/components/trade/verdict-prototypes";
import { usePortfolio } from "@/lib/store/collection-store";

type Scenario = "lose" | "fair" | "win";
const FACTOR: Record<Scenario, number> = { lose: 0.62, fair: 1.02, win: 1.45 };

/** Prototype page: six ways to show a trade's verdict, with a switch between losing, fair and winning trades. */
export default function TradeLabPage() {
  const { holdings } = usePortfolio({ ignoreFilter: true });
  const [scenario, setScenario] = useState<Scenario>("lose");

  const { giveItems, getItems } = useMemo(() => {
    const priced = holdings.filter((h) => h.product && h.price !== null).sort((a, b) => (b.price ?? 0) - (a.price ?? 0));
    const pick = (i: number) => priced[i % Math.max(1, priced.length)];
    const give: VerdictItem[] = [pick(1), pick(4)].filter(Boolean).map((h) => ({ key: `g:${h.key}`, product: h.product!, value: h.price! }));
    const giveTotal = give.reduce((s, i) => s + i.value, 0);
    // Sample "get" side: real products, values scaled so the scenario lands where it should.
    const getRaw = [pick(2), pick(6), pick(8)].filter(Boolean);
    const rawTotal = getRaw.reduce((s, h) => s + h.price!, 0) || 1;
    const scale = (giveTotal * FACTOR[scenario]) / rawTotal;
    const get: VerdictItem[] = getRaw.map((h) => ({ key: `t:${h.key}`, product: h.product!, value: Math.round(h.price! * scale * 100) / 100 }));
    return { giveItems: give, getItems: get };
  }, [holdings, scenario]);

  const props = {
    give: giveItems.reduce((s, i) => s + i.value, 0),
    get: getItems.reduce((s, i) => s + i.value, 0),
    giveItems,
    getItems,
  };

  const options = [
    { id: "A", name: "Net result", note: "The answer as one big number, and the sum behind it.", el: <VerdictNet {...props} /> },
    { id: "B", name: "Tug of war", note: "One bar split between the sides, with a line at even.", el: <VerdictTug {...props} /> },
    { id: "C", name: "Fairness meter", note: "A dial from you lose, through fair, to you win.", el: <VerdictGauge {...props} /> },
    { id: "D", name: "Two piles", note: "Each side as a pile that grows with its value.", el: <VerdictPiles {...props} /> },
    { id: "E", name: "Swap", note: "What leaves your collection, what comes in, and a stamp with the result.", el: <VerdictSwap {...props} /> },
    { id: "F", name: "Ledger", note: "Itemized like a statement, ending in the balance.", el: <VerdictLedger {...props} /> },
  ];
  const roundTwo = [
    { id: "G", name: "Trade grade", note: "The trade graded 1 to 10 on a slab label. 10 is a steal.", el: <VerdictGrade {...props} /> },
    { id: "H", name: "Versus", note: "You against them on a slant; the winner lights up and the VS slides toward the loser.", el: <VerdictVersus {...props} /> },
    { id: "I", name: "Steal-o-meter", note: "One word, then a spectrum from rip-off to steal with the result riding on it.", el: <VerdictMeter {...props} /> },
    { id: "J", name: "Pull", note: "The verdict flips in as a foil card, like opening a pack.", el: <VerdictPull {...props} /> },
    { id: "K", name: "Head to head", note: "Both sides as tinted cards, the gap as a chip between them.", el: <VerdictPlans {...props} /> },
    { id: "L", name: "Make it fair", note: "The gap, then the quickest ways to close it: cash, or keeping one card.", el: <VerdictFix {...props} /> },
  ];

  return (
    <div>
      <PageHeader title="Trade verdict lab" subtitle="Twelve ways to show whether a trade is fair, using sample trades from your collection" />
      <Segmented
        ariaLabel="Scenario"
        value={scenario}
        onChange={setScenario}
        options={[
          { value: "lose", label: "You lose" },
          { value: "fair", label: "Fair" },
          { value: "win", label: "You win" },
        ]}
      />
      <h2 className="mt-10 font-display text-[24px] uppercase">Round two</h2>
      <div className="mt-4 grid gap-6 md:grid-cols-2 xl:grid-cols-3">
        {roundTwo.map((o) => (
          <section key={o.id} className="min-w-0">
            <p className="mb-3 flex flex-wrap items-baseline gap-x-3 gap-y-1">
              <span className="tag-skew tag-lime">{o.id}</span>
              <span className="font-display text-[20px] uppercase tracking-[0.01em]">{o.name}</span>
            </p>
            <p className="mb-3 text-[13px] text-muted">{o.note}</p>
            <div className="rounded-[var(--radius-card)] border border-border bg-surface p-5">{o.el}</div>
          </section>
        ))}
      </div>
      <h2 className="mt-14 font-display text-[24px] uppercase text-muted">Round one</h2>
      <div className="mt-4 grid gap-6 md:grid-cols-2 xl:grid-cols-3">
        {options.map((o) => (
          <section key={o.id} className="min-w-0">
            <p className="mb-3 flex flex-wrap items-baseline gap-x-3 gap-y-1">
              <span className="tag-skew tag-lime">{o.id}</span>
              <span className="font-display text-[20px] uppercase tracking-[0.01em]">{o.name}</span>
            </p>
            <p className="mb-3 text-[13px] text-muted">{o.note}</p>
            <div className="rounded-[var(--radius-card)] border border-border bg-surface p-5">{o.el}</div>
          </section>
        ))}
      </div>
    </div>
  );
}
