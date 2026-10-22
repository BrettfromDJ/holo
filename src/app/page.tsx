"use client";

import { AlertCircle, CalendarDays, Layers, RefreshCw, TrendingDown, TrendingUp, Wallet } from "lucide-react";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { Delta } from "@/components/product/delta";
import { AllocationBar } from "@/components/portfolio/allocation-bar";
import { EmptyCollection } from "@/components/portfolio/empty-state";
import { ErrorState } from "@/components/portfolio/error-state";
import { HoldingMiniRow, HoldingTile } from "@/components/portfolio/holding-items";
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
  // Greeting depends on local time, so it's resolved after hydration.
  const [hello, setHello] = useState<string | null>(null);
  useEffect(() => setHello(greeting(new Date().getHours())), []);

  const movers = useMemo(() => {
    const withMove = holdings.map((h) => ({ h, m: moveOf(h, movePeriod) })).filter((x): x is { h: HoldingView; m: number } => x.m !== null);
    return {
      gainers: withMove.filter((x) => x.m > 0).sort((a, b) => b.m - a.m).slice(0, 5),
      losers: withMove.filter((x) => x.m < 0).sort((a, b) => a.m - b.m).slice(0, 5),
    };
  }, [holdings, movePeriod]);

  const mostValuable = useMemo(() => [...holdings].sort((a, b) => (b.value ?? -1) - (a.value ?? -1)).slice(0, 8), [holdings]);
  const recent = useMemo(() => [...holdings].sort((a, b) => ((b.lastAcquired ?? "") > (a.lastAcquired ?? "") ? 1 : -1)).slice(0, 5), [holdings]);
  const alloc = useMemo(() => allocation(holdings), [holdings]);
  const allTime = useMemo(() => performanceOf(timeline), [timeline]);
  const yearPerf = useMemo(() => performanceOf(timeline.filter((p) => p.date >= addYear(store.today))), [timeline, store.today]);

  if (store.status === "loading") return <OverviewSkeleton />;
  if (store.status === "error") return <ErrorState message={store.error} />;
  if (!store.data.transactions.length) return <EmptyCollection />;

  const totalReturn = summary.unrealized + summary.realized;
  const gainUp = (summary.unrealized ?? 0) >= 0;

  return (
    <div className="animate-fade-in">
      <header className="mb-8">
        <p className="flex items-center gap-2 text-[15px] text-muted">
          {longDate(store.today)}
          {store.mode === "demo" && <Badge variant="sample">Sample data</Badge>}
        </p>
        <h1 className="mt-1 text-[34px] font-bold tracking-[-0.03em] sm:text-[44px]">{hello ?? "Welcome back"}</h1>
      </header>

      <Card className="p-5 sm:p-8">
        <PerformanceChart
          timeline={timeline}
          header={(scrub) => (
            <div className="mb-4">
              <p className="text-[15px] font-medium text-muted">{scrub ? formatDate(scrub.date) : "Portfolio value"}</p>
              <p className="tabular mt-1 text-[48px] font-bold leading-none tracking-[-0.04em] sm:text-[64px]">{money(scrub ? scrub.value : summary.marketValue)}</p>
            </div>
          )}
        />
        <PriceFreshness />
      </Card>

      {summary.unpricedCount > 0 && (
        <p className="mt-4 flex items-center gap-3 rounded-2xl bg-surface-2 px-5 py-4 text-[14px] text-muted">
          <AlertCircle className="size-5 shrink-0" />
          {summary.unpricedCount} holding{summary.unpricedCount === 1 ? " has" : "s have"} no market price ({money(summary.unpricedCostBasis)} cost basis). {summary.unpricedCount === 1 ? "It's" : "They're"} excluded from value and gains — never counted as $0.
        </p>
      )}

      <section className="mt-6 grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-4" aria-label="Key metrics">
        <Tile tone="bg-lilac" icon={Wallet} label="Invested" value={money(summary.costBasis)} sub="Cost incl. fees & shipping" hint="Actual purchase cost of everything you currently hold, including allocated fees, shipping and tax (FIFO)." />
        <Tile
          tone={gainUp ? "bg-mint" : "bg-peach"}
          icon={gainUp ? TrendingUp : TrendingDown}
          label="Unrealized gain"
          value={<Delta value={summary.unrealized} />}
          sub={<Delta ratio={summary.unrealizedPct} pctOnly />}
          href="/gains"
        />
        <Tile
          tone="bg-sky"
          icon={CalendarDays}
          label="Today"
          value={<Delta value={summary.dayChange} />}
          sub={<Delta ratio={summary.dayChangePct} pctOnly />}
          hint="Change in market value of items held since yesterday. New purchases and sales are excluded."
        />
        <Tile tone="bg-peach" icon={Layers} label="Holdings" value={String(summary.holdingsCount)} sub={`${summary.unitCount} items in total`} href="/collection" />
      </section>

      <section className="mt-12" aria-label="Your showcase">
        <SectionTitle title="Your showcase" subtitle="Your most valuable pieces" action={<SeeAll href="/collection?sort=value" />} />
        <div className="scrollbar-none -mx-5 flex snap-x scroll-px-5 gap-4 overflow-x-auto px-5 pb-4 pt-1 sm:mx-0 sm:scroll-px-0 sm:px-0">
          {mostValuable.map((h) => (
            <div key={h.key} className="w-[210px] shrink-0 snap-start sm:w-[230px]">
              <HoldingTile h={h} />
            </div>
          ))}
        </div>
      </section>

      <div className="mt-8 grid gap-6 lg:grid-cols-2">
        <Card className="p-6 sm:p-7">
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
          <MoverList title="Gainers" items={movers.gainers} />
          <MoverList title="Losers" items={movers.losers} className="mt-5" />
        </Card>

        <div className="flex flex-col gap-6">
          <Card className="p-6 sm:p-7">
            <SectionTitle title="Sealed vs. singles" subtitle="Share of market value" />
            <AllocationBar slices={alloc} />
          </Card>

          <Card className="p-6 sm:p-7">
            <SectionTitle title="Performance" action={<SeeAll href="/gains" label="Gains" />} />
            <dl className="grid grid-cols-2 gap-x-6 gap-y-6">
              <Stat label="Total return" value={<Delta value={totalReturn} />} sub="Unrealized + realized" />
              <Stat label="Realized gains" value={<Delta value={summary.realized} />} sub="From completed sales" />
              <Stat label="Time-weighted, 1Y" value={<Delta ratio={yearPerf?.twr ?? null} pctOnly />} sub={yearPerf ? signedMoney(yearPerf.marketGain) + " market gain" : "—"} />
              <Stat label="Time-weighted, all" value={<Delta ratio={allTime?.twr ?? null} pctOnly />} sub={allTime ? `Since ${formatDate(allTime.start)}` : "—"} />
            </dl>
          </Card>
        </div>

        <Card className="p-6 sm:p-7 lg:col-span-2">
          <SectionTitle title="Recently added" action={<SeeAll href="/activity" label="Activity" />} />
          <div className="grid gap-x-10 sm:grid-cols-2">
            {recent.map((h) => (
              <HoldingMiniRow key={h.key} h={h} />
            ))}
          </div>
        </Card>
      </div>
    </div>
  );
}

function longDate(iso: string) {
  const d = new Date(`${iso}T12:00:00`);
  return d.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" });
}

function greeting(hour: number) {
  if (hour >= 5 && hour < 12) return "Good morning";
  if (hour >= 12 && hour < 18) return "Good afternoon";
  return "Good evening";
}

function addYear(today: string) {
  const [y, m, d] = today.split("-");
  return `${Number(y) - 1}-${m}-${d}`;
}

function Tile({
  tone,
  icon: Icon,
  label,
  value,
  sub,
  hint,
  href,
}: {
  tone: string;
  icon: React.ComponentType<{ className?: string }>;
  label: string;
  value: React.ReactNode;
  sub?: React.ReactNode;
  hint?: string;
  href?: string;
}) {
  const inner = (
    <div className={cn("flex h-full flex-col rounded-[1.75rem] p-5 transition-transform duration-300 ease-[var(--ease-apple)] sm:p-6", tone, href && "hover:-translate-y-1")}>
      <span className="flex size-10 items-center justify-center rounded-full bg-surface/80 shadow-card">
        <Icon className="size-5" />
      </span>
      <p className="mt-5 text-[14px] font-medium text-foreground/70">{label}</p>
      <p className="tabular mt-1 text-[22px] font-bold tracking-tight sm:text-[26px]">{value}</p>
      {sub && <p className="mt-0.5 text-[13px] font-medium text-foreground/60">{sub}</p>}
    </div>
  );
  if (href)
    return (
      <Link href={href} className="block rounded-[1.75rem]">
        {inner}
      </Link>
    );
  return hint ? (
    <Hint content={hint}>
      <div tabIndex={0} className="rounded-[1.75rem]">
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
      <dt className="text-[14px] text-muted">{label}</dt>
      <dd className="tabular mt-1 text-[22px] font-bold tracking-tight">{value}</dd>
      <dd className="mt-0.5 text-[13px] text-subtle">{sub}</dd>
    </div>
  );
}

function MoverList({ title, items, className }: { title: string; items: { h: HoldingView; m: number }[]; className?: string }) {
  return (
    <div className={className}>
      <p className="mb-1 text-[13px] font-semibold text-subtle">{title}</p>
      {items.length ? items.map(({ h, m }) => <HoldingMiniRow key={h.key} h={h} metric="change" change={m} />) : <p className="py-3 text-[15px] text-muted">No {title.toLowerCase()} in this period.</p>}
    </div>
  );
}

function SeeAll({ href, label = "See all" }: { href: string; label?: string }) {
  return (
    <Link href={href} className="rounded-full bg-surface-2 px-3.5 py-1.5 text-[14px] font-semibold text-foreground transition-colors hover:bg-surface-3">
      {label}
    </Link>
  );
}

function PriceFreshness() {
  const { mode, integrations, pricesRefreshedAt, refreshing, priceError, refreshPrices } = useStore();
  if (mode === "demo") return <p className="mt-4 text-[13px] text-subtle">Sample prices are generated for demonstration and are not market data.</p>;
  return (
    <div className="mt-4 flex flex-wrap items-center gap-x-3 gap-y-1 text-[13px] text-subtle">
      <span>{integrations.tcgapi ? `Prices from TCG API · refreshed ${relativeTime(pricesRefreshedAt)}` : "Live pricing isn't configured — showing last stored prices."}</span>
      {integrations.tcgapi && (
        <button onClick={() => void refreshPrices(true)} disabled={refreshing} className="inline-flex items-center gap-1 font-semibold text-muted hover:text-foreground disabled:opacity-50">
          <RefreshCw className={cn("size-3.5", refreshing && "animate-spin")} /> Refresh
        </button>
      )}
      {priceError && <span className="text-down">{priceError}</span>}
    </div>
  );
}

function OverviewSkeleton() {
  return (
    <div aria-busy="true" aria-label="Loading portfolio">
      <Skeleton className="h-4 w-40" />
      <Skeleton className="mt-3 h-11 w-72" />
      <Skeleton className="mt-8 h-[420px] w-full rounded-[var(--radius-card)]" />
      <div className="mt-6 grid grid-cols-2 gap-4 lg:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <Skeleton key={i} className="h-44 rounded-[var(--radius-card)]" />
        ))}
      </div>
    </div>
  );
}
