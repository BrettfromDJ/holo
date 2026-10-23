"use client";

import { AlertCircle, RefreshCw } from "lucide-react";
import Link from "next/link";
import { useMemo, useState } from "react";
import { Delta } from "@/components/product/delta";
import { AllocationBar } from "@/components/portfolio/allocation-bar";
import { EmptyCollection } from "@/components/portfolio/empty-state";
import { ErrorState } from "@/components/portfolio/error-state";
import { HoldingMiniRow } from "@/components/portfolio/holding-items";
import { PerformanceChart } from "@/components/portfolio/performance-chart";
import { Badge } from "@/components/ui/badge";
import { Card, SectionTitle } from "@/components/ui/card";
import { Segmented } from "@/components/ui/segmented";
import { Skeleton } from "@/components/ui/skeleton";
import { Hint } from "@/components/ui/tooltip";
import { allocation, performanceOf, type HoldingView } from "@/lib/finance/portfolio";
import { formatDate, money, relativeTime, signedMoney } from "@/lib/format";
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

  const movers = useMemo(() => {
    const withMove = holdings.map((h) => ({ h, m: moveOf(h, movePeriod) })).filter((x): x is { h: HoldingView; m: number } => x.m !== null);
    return {
      gainers: withMove.filter((x) => x.m > 0).sort((a, b) => b.m - a.m).slice(0, 5),
      losers: withMove.filter((x) => x.m < 0).sort((a, b) => a.m - b.m).slice(0, 5),
    };
  }, [holdings, movePeriod]);

  const mostValuable = useMemo(() => [...holdings].sort((a, b) => (b.value ?? -1) - (a.value ?? -1)).slice(0, 5), [holdings]);
  const recent = useMemo(() => [...holdings].sort((a, b) => ((b.lastAcquired ?? "") > (a.lastAcquired ?? "") ? 1 : -1)).slice(0, 5), [holdings]);
  const alloc = useMemo(() => allocation(holdings), [holdings]);
  const allTime = useMemo(() => performanceOf(timeline), [timeline]);
  const yearPerf = useMemo(() => performanceOf(timeline.filter((p) => p.date >= addYear(store.today))), [timeline, store.today]);

  if (store.status === "loading") return <OverviewSkeleton />;
  if (store.status === "error") return <ErrorState message={store.error} />;
  if (!store.data.transactions.length) return <EmptyCollection />;

  const totalReturn = summary.unrealized + summary.realized;

  return (
    <div className="animate-fade-in">
      <PerformanceChart
        timeline={timeline}
        header={(scrub) => (
          <div className="mb-3">
            <div className="flex items-center gap-2">
              <p className="text-[13px] font-medium text-muted">{scrub ? formatDate(scrub.date) : "Portfolio value"}</p>
              {store.mode === "demo" && <Badge variant="sample">Sample data</Badge>}
            </div>
            <p className="tabular mt-1 text-[44px] font-semibold leading-none tracking-[-0.035em] sm:text-[56px]">{money(scrub ? scrub.value : summary.marketValue)}</p>
          </div>
        )}
      />

      <section className="mt-8 grid grid-cols-2 gap-3 lg:grid-cols-4" aria-label="Key metrics">
        <Metric label="Total value" value={money(summary.marketValue)} sub={`${summary.holdingsCount} holdings · ${summary.unitCount} items`} />
        <Metric label="Total invested" value={money(summary.costBasis)} sub="Cost basis incl. fees & shipping" hint="Actual purchase cost of everything you currently hold, including allocated fees, shipping and tax (FIFO)." />
        <Link href="/gains" className="block rounded-2xl transition-opacity hover:opacity-90">
          <Metric
            label="Unrealized gain"
            value={<Delta value={summary.unrealized} />}
            sub={
              <span className="flex items-center justify-between gap-2">
                <Delta ratio={summary.unrealizedPct} pctOnly />
                <span className="text-subtle">See breakdown →</span>
              </span>
            }
          />
        </Link>
        <Metric
          label="Today"
          value={<Delta value={summary.dayChange} />}
          sub={<Delta ratio={summary.dayChangePct} pctOnly />}
          hint="Change in market value of items held since yesterday. New purchases and sales are excluded."
        />
      </section>

      <PriceFreshness />

      {summary.unpricedCount > 0 && (
        <p className="mt-4 flex items-center gap-2 rounded-xl bg-surface px-4 py-3 text-[13px] text-muted">
          <AlertCircle className="size-4 shrink-0" />
          {summary.unpricedCount} holding{summary.unpricedCount === 1 ? " has" : "s have"} no market price ({money(summary.unpricedCostBasis)} cost basis). {summary.unpricedCount === 1 ? "It's" : "They're"} excluded from value and gains — never counted as $0.
        </p>
      )}

      <div className="mt-10 grid gap-5 lg:grid-cols-2">
        <Card className="p-5 sm:p-6">
          <SectionTitle
            title="Top movers"
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
          <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-1 xl:grid-cols-2">
            <MoverList title="Gainers" items={movers.gainers} />
            <MoverList title="Losers" items={movers.losers} />
          </div>
        </Card>

        <Card className="p-5 sm:p-6">
          <SectionTitle title="Most valuable" action={<SeeAll href="/collection?sort=value" />} />
          {mostValuable.map((h) => (
            <HoldingMiniRow key={h.key} h={h} />
          ))}
        </Card>

        <Card className="p-5 sm:p-6">
          <SectionTitle title="Sealed vs. singles" subtitle="Share of market value" />
          <AllocationBar slices={alloc} />
        </Card>

        <Card className="p-5 sm:p-6">
          <SectionTitle title="Collection performance" action={<SeeAll href="/gains" label="Gains breakdown" />} />
          <dl className="grid grid-cols-2 gap-x-6 gap-y-5">
            <Stat label="Total return" value={<Delta value={totalReturn} />} sub="Unrealized + realized" />
            <Stat label="Realized gains" value={<Delta value={summary.realized} />} sub="From completed sales" />
            <Stat label="Time-weighted, 1Y" value={<Delta ratio={yearPerf?.twr ?? null} pctOnly />} sub={yearPerf ? signedMoney(yearPerf.marketGain) + " market gain" : "—"} />
            <Stat label="Time-weighted, all" value={<Delta ratio={allTime?.twr ?? null} pctOnly />} sub={allTime ? `Since ${formatDate(allTime.start)}` : "—"} />
          </dl>
        </Card>

        <Card className="p-5 sm:p-6 lg:col-span-2">
          <SectionTitle title="Recently added" action={<SeeAll href="/activity" label="Activity" />} />
          <div className="grid gap-x-8 sm:grid-cols-2">
            {recent.map((h) => (
              <HoldingMiniRow key={h.key} h={h} />
            ))}
          </div>
        </Card>
      </div>
    </div>
  );
}

function addYear(today: string) {
  const [y, m, d] = today.split("-");
  return `${Number(y) - 1}-${m}-${d}`;
}

function Metric({ label, value, sub, hint }: { label: string; value: React.ReactNode; sub?: React.ReactNode; hint?: string }) {
  const inner = (
    <div className="h-full rounded-2xl border border-border bg-surface p-4 sm:p-5">
      <p className="text-[12px] font-medium text-muted">{label}</p>
      <p className="tabular mt-2 text-[19px] font-semibold tracking-tight sm:text-[22px]">{value}</p>
      {sub && <p className="mt-1 text-[12px] text-muted">{sub}</p>}
    </div>
  );
  return hint ? (
    <Hint content={hint}>
      <div tabIndex={0} className="rounded-2xl">
        {inner}
      </div>
    </Hint>
  ) : (
    inner
  );
}

function Stat({ label, value, sub }: { label: string; value: React.ReactNode; sub: string }) {
  return (
    <div>
      <dt className="text-[12px] text-muted">{label}</dt>
      <dd className="tabular mt-1 text-[18px] font-semibold">{value}</dd>
      <dd className="mt-0.5 text-[12px] text-subtle">{sub}</dd>
    </div>
  );
}

function MoverList({ title, items }: { title: string; items: { h: HoldingView; m: number }[] }) {
  return (
    <div>
      <p className="mb-1 text-[12px] font-medium uppercase tracking-wider text-subtle">{title}</p>
      {items.length ? items.map(({ h, m }) => <HoldingMiniRow key={h.key} h={h} metric="change" change={m} />) : <p className="py-3 text-[13px] text-muted">No {title.toLowerCase()} in this period.</p>}
    </div>
  );
}

function SeeAll({ href, label = "See all" }: { href: string; label?: string }) {
  return (
    <Link href={href} className="text-[13px] font-medium text-muted transition-colors hover:text-foreground">
      {label}
    </Link>
  );
}

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
