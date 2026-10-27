"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { Area, Bar, BarChart, CartesianGrid, ComposedChart, Line, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { EmptyCollection } from "@/components/portfolio/empty-state";
import { ErrorState } from "@/components/portfolio/error-state";
import { HoldingMiniRow } from "@/components/portfolio/holding-items";
import { AllocationBar } from "@/components/portfolio/allocation-bar";
import { RANGES, RANGE_LABEL } from "@/components/portfolio/performance-chart";
import { Delta } from "@/components/product/delta";
import { PortfolioBanner, PortfolioSwitcher } from "@/components/portfolio/portfolio-controls";
import { PageHeader } from "@/components/shell/page-header";
import { Card, SectionTitle } from "@/components/ui/card";
import { Segmented } from "@/components/ui/segmented";
import { Skeleton } from "@/components/ui/skeleton";
import { allocation, monthlyActivity, performanceBySet, performanceOf, slicePoints } from "@/lib/finance/portfolio";
import { formatDate, formatMonth, formatShortDate, money, moneyCompact, pct, signedMoney } from "@/lib/format";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import type { ChartRange } from "@/lib/types";
import { cn } from "@/lib/utils";

const axisTick = { fill: "var(--subtle)", fontSize: 11 };

function ChartTooltip({ active, payload, label, rows }: { active?: boolean; payload?: { payload: Record<string, number | string> }[]; label?: string; rows: { key: string; label: string; color: string; signed?: boolean }[] }) {
  if (!active || !payload?.length) return null;
  const p = payload[0].payload;
  return (
    <div className="tabular min-w-44 rounded-xl border border-border bg-surface-3 px-3 py-2.5 text-[12px] shadow-xl">
      <p className="mb-1.5 text-muted">{label && label.length === 7 ? formatMonth(label) : formatDate(String(label))}</p>
      {rows.map((r) => (
        <div key={r.key} className="flex items-center justify-between gap-4">
          <span className="flex items-center gap-1.5 text-muted">
            <span className="size-2 rounded-full" style={{ background: r.color }} />
            {r.label}
          </span>
          <span className="font-medium text-foreground">{r.signed ? signedMoney(Number(p[r.key])) : money(Number(p[r.key]))}</span>
        </div>
      ))}
    </div>
  );
}

export default function AnalyticsPage() {
  const store = useStore();
  const { holdings, timeline, summary } = usePortfolio();
  const [range, setRange] = useState<ChartRange>("1Y");
  const [setSort, setSetSort] = useState<"value" | "return">("value");
  const [rankBy, setRankBy] = useState<"dollar" | "percent">("dollar");

  const slice = useMemo(() => slicePoints(timeline, range, store.today), [timeline, range, store.today]);
  const perf = performanceOf(slice);
  const history = useMemo(() => slice.map((p) => ({ date: p.date, value: p.value, invested: p.costBasisPriced, gain: p.unrealized })), [slice]);
  const alloc = useMemo(() => allocation(holdings), [holdings]);
  const sets = useMemo(() => {
    const rows = performanceBySet(holdings);
    return setSort === "value" ? rows : [...rows].sort((a, b) => (b.unrealizedPct ?? -Infinity) - (a.unrealizedPct ?? -Infinity));
  }, [holdings, setSort]);
  const monthly = useMemo(() => monthlyActivity(store.data, store.today).slice(-18), [store.data, store.today]);
  const ranked = useMemo(() => {
    const priced = holdings.filter((h) => h.unrealized !== null);
    const key = (h: (typeof priced)[number]) => (rankBy === "dollar" ? h.unrealized! : (h.unrealizedPct ?? 0));
    const sorted = [...priced].sort((a, b) => key(b) - key(a));
    return { best: sorted.filter((h) => h.unrealized! > 0).slice(0, 5), worst: sorted.reverse().filter((h) => h.unrealized! < 0).slice(0, 5) };
  }, [holdings, rankBy]);

  if (store.status === "loading") return <Skeleton className="h-[600px] w-full rounded-3xl" />;
  if (store.status === "error") return <ErrorState message={store.error} />;
  if (!store.data.transactions.length) {
    return (
      <>
        <PageHeader title="Analytics" />
        <EmptyCollection title="No data to analyze yet" />
      </>
    );
  }

  const maxShare = Math.max(...sets.map((s) => s.share), 0.0001);

  return (
    <div className="animate-fade-in">
      <PageHeader
        title="Analytics"
        subtitle="How your collection is allocated and how it has performed."
        actions={
          <Link href="/gains" className="text-[14px] font-medium text-muted hover:text-foreground">
            Gains breakdown →
          </Link>
        }
      />
      <PortfolioSwitcher compact className="mb-3 lg:hidden" />
      <PortfolioBanner />

      <Card className="min-w-0 p-5 sm:p-6">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <h2 className="text-[17px] font-semibold tracking-tight">Portfolio history</h2>
            <p className="tabular mt-1 text-[13px] text-muted">
              {perf ? (
                <>
                  <Delta value={perf.marketGain} ratio={perf.twr} className="font-medium" /> market performance · {RANGE_LABEL[range].toLowerCase()}
                </>
              ) : (
                "—"
              )}
            </p>
          </div>
          <Segmented ariaLabel="History range" size="sm" value={range} onChange={setRange} options={RANGES.map((r) => ({ value: r, label: r }))} />
        </div>
        <div className="mt-5 flex flex-wrap gap-4 text-[12px] text-muted">
          <Legend color="var(--foreground)" label="Market value" />
          <Legend color="var(--subtle)" label="Cost basis (priced holdings)" dashed />
        </div>
        <div className="mt-3 h-[260px]">
          <ResponsiveContainer>
            <ComposedChart data={history} margin={{ top: 8, right: 0, left: 0, bottom: 0 }}>
              <CartesianGrid vertical={false} stroke="var(--chart-grid)" />
              <XAxis dataKey="date" tick={axisTick} tickLine={false} axisLine={false} tickFormatter={formatShortDate} minTickGap={48} />
              <YAxis orientation="right" tick={axisTick} tickLine={false} axisLine={false} width={56} tickFormatter={moneyCompact} domain={["auto", "auto"]} />
              <Tooltip
                cursor={{ stroke: "var(--border-strong)" }}
                content={(p) => (
                  <ChartTooltip
                    {...(p as object)}
                    label={String(p.label)}
                    rows={[
                      { key: "value", label: "Value", color: "var(--foreground)" },
                      { key: "invested", label: "Cost basis", color: "var(--subtle)" },
                      { key: "gain", label: "Unrealized", color: "var(--up)", signed: true },
                    ]}
                  />
                )}
              />
              <Line type="monotone" dataKey="invested" stroke="var(--subtle)" strokeWidth={1.5} strokeDasharray="4 4" dot={false} isAnimationActive={false} />
              <Line type="monotone" dataKey="value" stroke="var(--foreground)" strokeWidth={2} dot={false} activeDot={{ r: 4, strokeWidth: 2, stroke: "var(--surface)" }} isAnimationActive={false} />
            </ComposedChart>
          </ResponsiveContainer>
        </div>
        <div className="mt-6 border-t border-border pt-5">
          <p className="text-[12px] font-medium text-muted">Unrealized gain / loss</p>
          <div className="mt-2 h-[120px]">
            <ResponsiveContainer>
              <ComposedChart data={history} margin={{ top: 4, right: 0, left: 0, bottom: 0 }}>
                <XAxis dataKey="date" hide />
                <YAxis orientation="right" tick={axisTick} tickLine={false} axisLine={false} width={56} tickFormatter={moneyCompact} />
                <ReferenceLine y={0} stroke="var(--border-strong)" />
                <Tooltip cursor={{ stroke: "var(--border-strong)" }} content={(p) => <ChartTooltip {...(p as object)} label={String(p.label)} rows={[{ key: "gain", label: "Unrealized", color: "var(--up)", signed: true }]} />} />
                <Area type="monotone" dataKey="gain" stroke={summary.unrealized >= 0 ? "var(--up)" : "var(--down)"} fill={summary.unrealized >= 0 ? "var(--up-soft)" : "var(--down-soft)"} strokeWidth={1.5} isAnimationActive={false} />
              </ComposedChart>
            </ResponsiveContainer>
          </div>
        </div>
      </Card>

      <div className="mt-5 grid grid-cols-1 gap-5 lg:grid-cols-2">
        <Card className="min-w-0 p-5 sm:p-6">
          <SectionTitle title="Allocation" subtitle="Exposure by market value" />
          <AllocationBar slices={alloc} showCost />
        </Card>

        <Card className="min-w-0 p-5 sm:p-6">
          <SectionTitle title="Investment activity" subtitle="Money invested per month, incl. fees" />
          <div className="h-[220px]">
            <ResponsiveContainer>
              <BarChart data={monthly} margin={{ top: 8, right: 0, left: 0, bottom: 0 }}>
                <CartesianGrid vertical={false} stroke="var(--chart-grid)" />
                <XAxis dataKey="month" tick={axisTick} tickLine={false} axisLine={false} tickFormatter={formatMonth} minTickGap={16} />
                <YAxis orientation="right" tick={axisTick} tickLine={false} axisLine={false} width={48} tickFormatter={moneyCompact} />
                <Tooltip
                  cursor={{ fill: "var(--surface-2)" }}
                  content={(p) => (
                    <ChartTooltip
                      {...(p as object)}
                      label={String(p.label)}
                      rows={[
                        { key: "invested", label: "Invested", color: "var(--cat-1)" },
                        { key: "proceeds", label: "Sales", color: "var(--subtle)" },
                      ]}
                    />
                  )}
                />
                <Bar dataKey="invested" fill="var(--cat-1)" radius={[4, 4, 0, 0]} maxBarSize={28} isAnimationActive={false} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </Card>

        <Card className="min-w-0 p-5 sm:p-6 lg:col-span-2">
          <SectionTitle
            title="Performance by set"
            action={
              <Segmented
                ariaLabel="Sort sets"
                size="sm"
                value={setSort}
                onChange={setSetSort}
                options={[
                  { value: "value", label: "Value" },
                  { value: "return", label: "Return" },
                ]}
              />
            }
          />
          {/* Stacked rows on phones; a four-column grid from sm up. */}
          <div className="hidden grid-cols-[minmax(0,1.5fr)_minmax(0,1fr)_7rem_7rem] gap-4 pb-3 text-[12px] font-medium text-subtle sm:grid">
            <span>Set</span>
            <span>Share of value</span>
            <span className="text-right">Value</span>
            <span className="text-right">Unrealized</span>
          </div>
          <ul className="divide-y divide-border text-[14px]">
            {sets.map((s) => (
              <li key={s.setName} className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-4 gap-y-2 py-3 sm:grid-cols-[minmax(0,1.5fr)_minmax(0,1fr)_7rem_7rem]">
                <div className="min-w-0">
                  <p className="truncate font-medium">{s.setName}</p>
                  <p className="text-[12px] text-muted">
                    {s.holdings} holding{s.holdings === 1 ? "" : "s"}
                  </p>
                </div>
                <div className="col-span-2 row-start-2 flex items-center gap-2 sm:col-span-1 sm:col-start-2 sm:row-start-1">
                  <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-surface-2">
                    <div className="h-full rounded-full bg-cat-1" style={{ width: `${(s.share / maxShare) * 100}%` }} />
                  </div>
                  <span className="tabular w-10 text-right text-[12px] text-muted">{pct(s.share, 0)}</span>
                </div>
                <div className="text-right sm:contents">
                  <p className="tabular font-medium sm:text-right">{money(s.value)}</p>
                  <div className="sm:text-right">
                    <Delta value={s.unrealized} className="text-[12px] sm:block sm:text-[14px]" />
                    <Delta ratio={s.unrealizedPct} pctOnly className="ml-1.5 text-[12px] sm:ml-0 sm:block" />
                  </div>
                </div>
              </li>
            ))}
          </ul>
        </Card>

        <RankCard title="Best investments" items={ranked.best} rankBy={rankBy} setRankBy={setRankBy} empty="No holdings are in profit yet." />
        <RankCard title="Underperformers" items={ranked.worst} rankBy={rankBy} setRankBy={setRankBy} empty="Nothing is below cost. Nice." />
      </div>
      <p className="mt-6 text-[12px] text-subtle">
        Performance percentages are time-weighted: daily market returns are chained so that purchases and sales never count as gains. History starts {timeline[0] ? formatDate(timeline[0].date) : "—"}.
      </p>
    </div>
  );
}

function Legend({ color, label, dashed }: { color: string; label: string; dashed?: boolean }) {
  return (
    <span className="flex items-center gap-2">
      <span className={cn("inline-block w-4 border-t-2", dashed && "border-dashed")} style={{ borderColor: color }} aria-hidden />
      {label}
    </span>
  );
}

function RankCard({
  title,
  items,
  rankBy,
  setRankBy,
  empty,
}: {
  title: string;
  items: ReturnType<typeof usePortfolio>["holdings"];
  rankBy: "dollar" | "percent";
  setRankBy: (v: "dollar" | "percent") => void;
  empty: string;
}) {
  return (
    <Card className="min-w-0 p-5 sm:p-6">
      <SectionTitle
        title={title}
        action={
          <Segmented
            ariaLabel="Rank by"
            size="sm"
            value={rankBy}
            onChange={setRankBy}
            options={[
              { value: "dollar", label: "$" },
              { value: "percent", label: "%" },
            ]}
          />
        }
      />
      {items.length ? items.map((h) => <HoldingMiniRow key={h.key} h={h} />) : <p className="py-4 text-[14px] text-muted">{empty}</p>}
    </Card>
  );
}
