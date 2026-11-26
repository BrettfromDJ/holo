"use client";

import { useMemo } from "react";
import { AdvancedStats, Breakdown, ByMonth, Diversification, HistorySection, WinnersLosers } from "@/components/analytics/analytics-items";
import { GlassStat, toneOf } from "@/components/analytics/bits";
import { DeltaPill } from "@/components/product/delta";
import { EmptyCollection } from "@/components/portfolio/empty-state";
import { ErrorState } from "@/components/portfolio/error-state";
import { PortfolioBanner, PortfolioSwitcher } from "@/components/portfolio/portfolio-controls";
import { PageHeader } from "@/components/shell/page-header";
import { Skeleton } from "@/components/ui/skeleton";
import { averageHoldDays, concentration, monthlyReturns, returnVsTime, riskStats } from "@/lib/finance/analytics";
import { monthlyActivity } from "@/lib/finance/portfolio";
import { formatDate, money, signedMoney, signedPct } from "@/lib/format";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { holdingKey } from "@/lib/types";

/**
 * Analytics, like the app's redo: seven sections, each figure said once. The total return and its
 * one chart, winners and losers, the breakdown, month by month, how spread out it is, and the rarer
 * measures folded away. Percentages are time-weighted: buying and selling never count as gains.
 */
export default function AnalyticsPage() {
  const store = useStore();
  const { holdings, timeline, summary } = usePortfolio();

  const risk = useMemo(() => riskStats(timeline), [timeline]);
  const months = useMemo(() => monthlyReturns(timeline), [timeline]);
  const conc = useMemo(() => concentration(holdings), [holdings]);
  const held = useMemo(() => returnVsTime(holdings, store.today), [holdings, store.today]);
  // Money put in each month, for the selected portfolio, the last 12 months.
  const activity = useMemo(() => {
    const keep = store.holdingFilter;
    const transactions = keep ? store.data.transactions.filter((t) => keep(holdingKey(t))) : store.data.transactions;
    return monthlyActivity({ ...store.data, transactions }, store.today).slice(-12);
  }, [store.data, store.holdingFilter, store.today]);

  if (store.status === "loading") return <Skeleton className="h-[600px] w-full rounded-3xl" />;
  if (store.status === "error") return <ErrorState message={store.error} />;
  if (!store.data.transactions.length) {
    return (
      <>
        <PageHeader title="Analytics" />
        <EmptyCollection title="No numbers yet" body="Your numbers appear after your first card." />
      </>
    );
  }

  const total = summary.unrealized + summary.realized;

  return (
    <div className="animate-fade-in">
      <PageHeader
        title="Total return"
        figure={<span className={total >= 0 ? "text-lime" : "text-[var(--plan-pink)]"}>{signedMoney(total)}</span>}
        note={
          <span className="flex items-center gap-2">
            {summary.costBasis > 0 && <DeltaPill ratio={total / summary.costBasis} />}
            on {money(summary.costBasis)} invested
          </span>
        }
        className="mb-5"
      />
      <PortfolioSwitcher compact className="mb-3 lg:hidden" />
      <PortfolioBanner />

      <div className="flex min-w-0 flex-col gap-11">
        <section className="space-y-[18px]">
          <HistorySection timeline={timeline} today={store.today} />
          <div className="flex gap-2">
            <GlassStat label="Market only" value={signedPct(risk.totalReturn)} tone={toneOf(risk.totalReturn)} />
            <GlassStat label="Realized" value={signedMoney(summary.realized)} tone={toneOf(summary.realized)} href="/sales" />
            <GlassStat label="Invested" value={money(summary.costBasis)} />
          </div>
        </section>

        <div className="grid gap-11 lg:grid-cols-2 lg:gap-x-10 [&>*]:min-w-0">
          <WinnersLosers holdings={holdings} />
          <Breakdown holdings={holdings} />
        </div>
        <div className="grid gap-11 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)] lg:gap-x-10 [&>*]:min-w-0">
          <ByMonth months={months} risk={risk} activity={activity} />
          <Diversification c={conc} holdings={holdings} />
        </div>
        <AdvancedStats risk={risk} points={held} avgDays={averageHoldDays(held)} />
        <p className="text-[12px] text-subtle">
          Percentages are time-weighted, so buying and selling never count as gains. History starts {timeline[0] ? formatDate(timeline[0].date) : "—"}.
        </p>
      </div>
    </div>
  );
}
