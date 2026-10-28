"use client";

import { AlertCircle, RefreshCw } from "lucide-react";
import { useMemo, useState } from "react";
import { Delta } from "@/components/product/delta";
import { Reveal } from "@/components/motion/reveal";
import { MoversBoard, RecentTimeline } from "@/components/overview/boards";
import { BudgetCard } from "@/components/overview/budget-card";
import { PortfolioBanner, PortfolioSwitcher } from "@/components/portfolio/portfolio-controls";
import { MarketPulse } from "@/components/overview/market-pulse";
import { ReleaseReminders } from "@/components/overview/release-reminders";
import { MetricStrip, Shelf, Spotlight } from "@/components/overview/sections";
import { HypeHeading, HypeHero } from "@/components/overview/hype-hero";
import { WeeklyRecap } from "@/components/overview/weekly-recap";
import { AllocationShowcase } from "@/components/portfolio/allocation-showcase";
import { EmptyCollection } from "@/components/portfolio/empty-state";
import { ErrorState } from "@/components/portfolio/error-state";
import { PerformanceChart } from "@/components/portfolio/performance-chart";
import { Badge } from "@/components/ui/badge";
import { Segmented } from "@/components/ui/segmented";
import { Skeleton } from "@/components/ui/skeleton";
import type { HoldingView } from "@/lib/finance/portfolio";
import { formatDate, money, relativeTime, signedPct } from "@/lib/format";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";

type MovePeriod = "1D" | "7D" | "30D";

function moveOf(h: HoldingView, p: MovePeriod): number | null {
  if (p === "1D") return h.dayChangePct;
  const v = p === "7D" ? h.change7dPct : h.change30dPct;
  return v === null ? null : v / 100;
}

export default function OverviewPage() {
  const store = useStore();
  const { holdings, summary, timeline } = usePortfolio();
  const [movePeriod, setMovePeriod] = useState<MovePeriod>("1D");
  const [recapOpen, setRecapOpen] = useState(false);

  const movers = useMemo(() => {
    const withMove = holdings.map((h) => ({ h, m: moveOf(h, movePeriod) })).filter((x): x is { h: HoldingView; m: number } => x.m !== null);
    return {
      gainers: withMove.filter((x) => x.m > 0).sort((a, b) => b.m - a.m).slice(0, 5),
      losers: withMove.filter((x) => x.m < 0).sort((a, b) => a.m - b.m).slice(0, 5),
    };
  }, [holdings, movePeriod]);

  const recent = useMemo(() => [...holdings].sort((a, b) => ((b.lastAcquired ?? "") > (a.lastAcquired ?? "") ? 1 : -1)).slice(0, 5), [holdings]);

  if (store.status === "loading") return <OverviewSkeleton />;
  if (store.status === "error") return <ErrorState message={store.error} />;
  if (!store.data.transactions.length) {
    return <EmptyCollection />;
  }

  return (
    <div className="hype animate-fade-in">
      <MarketPulse holdings={holdings} />
      <PortfolioSwitcher compact className="mb-4 lg:hidden" />
      <PortfolioBanner />
      <HypeHero holdings={holdings} summary={summary} onRecap={() => setRecapOpen(true)} />
      <div className="h-6" />
      <WeeklyRecap open={recapOpen} onClose={() => setRecapOpen(false)} />
      <ReleaseReminders />

      <PerformanceChart
        timeline={timeline}
        header={(scrub) => (
          <div className="mb-3">
            <HypeHeading title="Performance" action={store.mode === "demo" ? <Badge variant="sample">Sample data</Badge> : undefined} />
            {/* The hero already shows today's value; here it follows the scrubbed day. */}
            <p className="tabular -mt-2 text-[13px] text-muted">
              {scrub ? (
                <>
                  {formatDate(scrub.date)} · <span className="font-semibold text-foreground">{money(scrub.value)}</span>
                </>
              ) : (
                "Drag across the chart to see any day"
              )}
            </p>
          </div>
        )}
      />

      <div className="mt-8">
        <MetricStrip
          tinted
          items={[
            { label: "Invested", value: money(summary.costBasis), sub: "incl. fees & shipping", tint: "tint-azure" },
            {
              label: "Unrealized",
              value: <Delta value={summary.unrealized} />,
              sub: "breakdown →",
              href: "/gains",
              tint: summary.unrealized >= 0 ? "tint-lime" : "tint-pink",
              tag: summary.unrealizedPct !== null && <span className={cn("tag-skew", summary.unrealized >= 0 ? "tag-lime" : "tag-pink")}>{signedPct(summary.unrealizedPct, 0)}</span>,
            },
            {
              label: "Today",
              value: <Delta value={summary.dayChange} />,
              tint: summary.dayChange >= 0 ? "tint-lime" : "tint-pink",
              tag: summary.dayChangePct !== null && <span className={cn("tag-skew", summary.dayChange >= 0 ? "tag-lime" : "tag-pink")}>{signedPct(summary.dayChangePct)}</span>,
            },
            { label: "Collection", value: `${summary.unitCount} items`, sub: `${summary.holdingsCount} products`, href: "/collection", tint: "tint-blue", tag: <span className="tag-skew tag-blue">{summary.holdingsCount} SKUs</span> },
          ]}
        />
        <BudgetCard />
        <PriceFreshness />
      </div>

      {summary.unpricedCount > 0 && (
        <p className="mt-4 flex items-center gap-2 rounded-xl bg-surface px-4 py-3 text-[13px] text-muted">
          <AlertCircle className="size-4 shrink-0" />
          {summary.unpricedCount} holding{summary.unpricedCount === 1 ? " has" : "s have"} no market price ({money(summary.unpricedCostBasis)} cost basis). {summary.unpricedCount === 1 ? "It's" : "They're"} excluded from value and gains — never counted as $0.
        </p>
      )}

      <div className="mt-14 space-y-14">
        <Reveal>
          <Spotlight holdings={holdings} />
        </Reveal>

        <Reveal>
          <Shelf holdings={holdings} subtitle="Your most valuable pieces" />
        </Reveal>

        <Reveal as="section">
          <SectionHeading title="Sealed vs. singles" subtitle="Where your collection's value sits" />
          <AllocationShowcase holdings={holdings} />
        </Reveal>

        <Reveal as="section">
          <SectionHeading
            title="Movers"
            action={
              <Segmented
                ariaLabel="Mover period"
                size="sm"
                value={movePeriod}
                onChange={setMovePeriod}
                options={[
                  { value: "1D", label: "1D" },
                  { value: "7D", label: "7D" },
                  { value: "30D", label: "30D" },
                ]}
              />
            }
          />
          <MoversBoard gainers={movers.gainers} losers={movers.losers} daily={movePeriod === "1D"} />
        </Reveal>

        <Reveal>
          <RecentTimeline holdings={recent} />
        </Reveal>
      </div>
    </div>
  );
}

const SectionHeading = HypeHeading;

function PriceFreshness() {
  const { mode, integrations, pricesRefreshedAt, refreshing, priceError, refreshPrices } = useStore();
  if (mode === "demo") return <p className="mt-3 text-[12px] text-subtle">Sample prices are generated for demonstration and are not market data.</p>;
  return (
    <div className="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1 text-[12px] text-subtle">
      <span>{integrations.tcgapi ? `Prices from TCG API · refreshed ${relativeTime(pricesRefreshedAt)} · updates daily` : "Live pricing isn't configured — showing last stored prices."}</span>
      {integrations.tcgapi && (
        <button onClick={() => void refreshPrices(true)} disabled={refreshing} className="inline-flex items-center gap-1 font-medium text-muted hover:text-foreground disabled:opacity-50">
          <RefreshCw className={cn("size-3", refreshing && "animate-spin")} /> Refresh
        </button>
      )}
      {priceError && <span className="text-down">{priceError}</span>}
    </div>
  );
}

function OverviewSkeleton() {
  return (
    <div aria-busy="true" aria-label="Loading portfolio">
      <Skeleton className="h-4 w-28" />
      <Skeleton className="mt-3 h-14 w-72" />
      <Skeleton className="mt-6 h-[280px] w-full rounded-3xl" />
      <div className="mt-8 grid grid-cols-2 gap-3 lg:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <Skeleton key={i} className="h-28" />
        ))}
      </div>
    </div>
  );
}
