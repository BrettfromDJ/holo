"use client";

import { AlertCircle, RefreshCw, Sparkles } from "lucide-react";
import Link from "next/link";
import { useMemo, useState } from "react";
import { Delta } from "@/components/product/delta";
import { CATEGORY_META } from "@/components/portfolio/allocation-bar";
import { EmptyCollection } from "@/components/portfolio/empty-state";
import { ErrorState } from "@/components/portfolio/error-state";
import { HoldingMiniRow } from "@/components/portfolio/holding-items";
import { PerformanceChart } from "@/components/portfolio/performance-chart";
import { Badge } from "@/components/ui/badge";
import { Card, SectionTitle } from "@/components/ui/card";
import { Segmented } from "@/components/ui/segmented";
import { Skeleton } from "@/components/ui/skeleton";
import { TickMeter } from "@/components/ui/tick-meter";
import { Hint } from "@/components/ui/tooltip";
import { allocation, performanceOf, type HoldingView } from "@/lib/finance/portfolio";
import { formatDate, money, pct, relativeTime, signedMoney, signedPct, tone } from "@/lib/format";
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
  const dayTone = tone(summary.dayChangePct);
  const mood = dayTone === "up" ? "up" : dayTone === "down" ? "down" : "steady";
  const topGainer = movers.gainers[0];
  const topLoser = movers.losers[0];

  return (
    <div className="grid animate-fade-in gap-5 lg:grid-cols-[minmax(0,1.08fr)_minmax(0,1fr)]">
      {/* Left: the market panel */}
      <Card className="self-start p-5 sm:p-6 lg:sticky lg:top-20">
        <PerformanceChart
          timeline={timeline}
          header={(scrub) => (
            <div className="mb-4">
              <div className="flex items-center gap-2">
                <p className="text-[12px] text-muted">{scrub ? formatDate(scrub.date) : longDate(store.today)}</p>
                {store.mode === "demo" && <Badge variant="sample">Sample data</Badge>}
              </div>
              <p className="mt-0.5 text-[15px] font-semibold tracking-tight">
                Your collection is <span className={cn(mood === "up" ? "text-up" : mood === "down" ? "text-down" : "text-muted")}>{mood}</span>
              </p>
              <p className="tabular mt-3 text-[34px] font-semibold leading-none tracking-[-0.03em] sm:text-[40px]">{money(scrub ? scrub.value : summary.marketValue)}</p>
            </div>
          )}
        />

        <dl className="mt-6 grid grid-cols-2 gap-px overflow-hidden rounded-xl border border-border bg-border sm:grid-cols-4" aria-label="Key metrics">
          <Metric label="Total value" value={money(summary.marketValue)} sub={`${summary.holdingsCount} holdings · ${summary.unitCount} items`} />
          <Metric label="Invested" value={money(summary.costBasis)} sub="Cost basis" hint="Actual purchase cost of everything you currently hold, including allocated fees, shipping and tax (FIFO)." />
          <Metric label="Unrealized" value={<Delta value={summary.unrealized} />} sub={<Delta ratio={summary.unrealizedPct} pctOnly />} href="/gains" />
          <Metric
            label="Today"
            value={<Delta value={summary.dayChange} />}
            sub={<Delta ratio={summary.dayChangePct} pctOnly />}
            hint="Change in market value of items held since yesterday. New purchases and sales are excluded."
          />
        </dl>

        {summary.unpricedCount > 0 && (
          <p className="mt-4 flex items-center gap-2 rounded-lg bg-surface-2/60 px-3 py-2.5 text-[12px] text-muted">
            <AlertCircle className="size-3.5 shrink-0" />
            {summary.unpricedCount} holding{summary.unpricedCount === 1 ? " has" : "s have"} no market price ({money(summary.unpricedCostBasis)} cost basis). {summary.unpricedCount === 1 ? "It's" : "They're"} excluded from value and gains — never counted as $0.
          </p>
        )}

        <div className="mt-6 rounded-xl border border-border bg-background/40 p-4">
          <p className="mb-1 text-[12px] font-medium text-muted">Allocation</p>
          <ul className="divide-y divide-border">
            {alloc
              .filter((a) => a.value > 0 || a.count > 0)
              .map((a) => (
                <li key={a.category} className="flex items-center gap-3 py-2 text-[13px]">
                  <span className="size-2 rounded-[2px]" style={{ background: CATEGORY_META[a.category].color }} aria-hidden />
                  <span className="flex-1">
                    {CATEGORY_META[a.category].label} <span className="text-subtle">· {a.count}</span>
                  </span>
                  <span className="tabular w-20 text-right font-medium">{money(a.value)}</span>
                  <span className="tabular w-10 text-right text-muted">{pct(a.share, 0)}</span>
                  <TickMeter value={a.share} color={CATEGORY_META[a.category].color} className="hidden sm:inline-flex" />
                </li>
              ))}
          </ul>
        </div>
      </Card>

      {/* Right: recap + lists */}
      <div className="flex min-w-0 flex-col gap-4">
        <Card className="relative overflow-hidden p-5">
          <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(120%_90%_at_100%_0%,var(--violet-soft),transparent_60%)]" aria-hidden />
          <div className="relative">
            <div className="flex items-center justify-between gap-3">
              <span className="inline-flex items-center gap-1.5 rounded-md bg-surface-3/70 px-2 py-1 text-[11px] font-medium">
                <Sparkles className="size-3 text-violet" /> Daily recap
              </span>
              <PriceFreshness />
            </div>
            <p className="mt-4 text-[15px] font-medium leading-relaxed tracking-tight">
              Your collection is worth {money(summary.marketValue)}, {dayTone === "flat" ? "unchanged" : `${dayTone === "up" ? "up" : "down"} ${money(Math.abs(summary.dayChange ?? 0))}`} today.{" "}
              {topGainer && (
                <>
                  {topGainer.h.product?.name ?? "A holding"} led the gainers at <span className="text-up">{signedPct(topGainer.m)}</span>.{" "}
                </>
              )}
              {topLoser && (
                <>
                  {topLoser.h.product?.name ?? "A holding"} lagged at <span className="text-down">{signedPct(topLoser.m)}</span>.{" "}
                </>
              )}
              <span className="text-muted">
                Overall you&apos;re <Delta value={summary.unrealized} className="font-medium" /> on what you hold.{" "}
                <Link href="/gains" className="text-foreground underline decoration-border-strong underline-offset-4 hover:decoration-foreground">
                  See breakdown
                </Link>
              </span>
            </p>
          </div>
        </Card>

        <Card className="p-5">
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
          <div className="grid gap-5 sm:grid-cols-2">
            <MoverList title="Gainers" items={movers.gainers} />
            <MoverList title="Losers" items={movers.losers} />
          </div>
        </Card>

        <Card className="p-5">
          <SectionTitle title="Most valuable" action={<SeeAll href="/collection?sort=value" />} />
          {mostValuable.map((h) => (
            <HoldingMiniRow key={h.key} h={h} />
          ))}
        </Card>

        <Card className="p-5">
          <SectionTitle title="Performance" action={<SeeAll href="/gains" label="Gains breakdown" />} />
          <dl className="grid grid-cols-2 gap-x-6 gap-y-4">
            <Stat label="Total return" value={<Delta value={totalReturn} />} sub="Unrealized + realized" />
            <Stat label="Realized gains" value={<Delta value={summary.realized} />} sub="From completed sales" />
            <Stat label="Time-weighted, 1Y" value={<Delta ratio={yearPerf?.twr ?? null} pctOnly />} sub={yearPerf ? signedMoney(yearPerf.marketGain) + " market gain" : "—"} />
            <Stat label="Time-weighted, all" value={<Delta ratio={allTime?.twr ?? null} pctOnly />} sub={allTime ? `Since ${formatDate(allTime.start)}` : "—"} />
          </dl>
        </Card>

        <Card className="p-5">
          <SectionTitle title="Recently added" action={<SeeAll href="/activity" label="Activity" />} />
          {recent.map((h) => (
            <HoldingMiniRow key={h.key} h={h} />
          ))}
        </Card>
      </div>
    </div>
  );
}

function longDate(iso: string) {
  const d = new Date(`${iso}T12:00:00`);
  return d.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" });
}

function addYear(today: string) {
  const [y, m, d] = today.split("-");
  return `${Number(y) - 1}-${m}-${d}`;
}

function Metric({ label, value, sub, hint, href }: { label: string; value: React.ReactNode; sub?: React.ReactNode; hint?: string; href?: string }) {
  const inner = (
    <div className="h-full bg-stage p-3.5 transition-colors">
      <dt className="text-[11px] text-muted">{label}</dt>
      <dd className="tabular mt-1.5 text-[15px] font-semibold tracking-tight">{value}</dd>
      {sub && <dd className="mt-0.5 truncate text-[11px] text-muted">{sub}</dd>}
    </div>
  );
  if (href)
    return (
      <Link href={href} className="block [&>div]:hover:bg-surface-2">
        {inner}
      </Link>
    );
  return hint ? (
    <Hint content={hint}>
      <div tabIndex={0}>{inner}</div>
    </Hint>
  ) : (
    inner
  );
}

function Stat({ label, value, sub }: { label: string; value: React.ReactNode; sub: string }) {
  return (
    <div>
      <dt className="text-[11px] text-muted">{label}</dt>
      <dd className="tabular mt-1 text-[16px] font-semibold">{value}</dd>
      <dd className="mt-0.5 text-[11px] text-subtle">{sub}</dd>
    </div>
  );
}

function MoverList({ title, items }: { title: string; items: { h: HoldingView; m: number }[] }) {
  return (
    <div>
      <p className="mb-1 text-[11px] font-medium text-subtle">{title}</p>
      {items.length ? items.map(({ h, m }) => <HoldingMiniRow key={h.key} h={h} metric="change" change={m} />) : <p className="py-3 text-[12px] text-muted">No {title.toLowerCase()} in this period.</p>}
    </div>
  );
}

function SeeAll({ href, label = "See all" }: { href: string; label?: string }) {
  return (
    <Link href={href} className="rounded-md px-2 py-1 text-[12px] font-medium text-muted transition-colors hover:bg-surface-2 hover:text-foreground">
      {label}
    </Link>
  );
}

function PriceFreshness() {
  const { mode, integrations, pricesRefreshedAt, refreshing, priceError, refreshPrices } = useStore();
  if (mode === "demo") return <span className="text-[11px] text-subtle">Sample prices</span>;
  if (priceError) return <span className="truncate text-[11px] text-down">{priceError}</span>;
  if (!integrations.tcgapi) return <span className="text-[11px] text-subtle">Live pricing off</span>;
  return (
    <button
      onClick={() => void refreshPrices(true)}
      disabled={refreshing}
      title="Refresh prices from TCG API"
      className="inline-flex items-center gap-1 text-[11px] text-subtle transition-colors hover:text-foreground disabled:opacity-50"
    >
      Refreshed {relativeTime(pricesRefreshedAt)}
      <RefreshCw className={cn("size-3", refreshing && "animate-spin")} />
    </button>
  );
}

function OverviewSkeleton() {
  return (
    <div aria-busy="true" aria-label="Loading portfolio" className="grid gap-5 lg:grid-cols-[minmax(0,1.08fr)_minmax(0,1fr)]">
      <Skeleton className="h-[560px] w-full rounded-[var(--radius-card)]" />
      <div className="flex flex-col gap-4">
        <Skeleton className="h-36 rounded-[var(--radius-card)]" />
        <Skeleton className="h-60 rounded-[var(--radius-card)]" />
        <Skeleton className="h-60 rounded-[var(--radius-card)]" />
      </div>
    </div>
  );
}
