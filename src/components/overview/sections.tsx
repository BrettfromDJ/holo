"use client";

import { ArrowRight, Flame, Sparkles, TrendingDown } from "lucide-react";
import Link from "next/link";
import { useMemo } from "react";
import { AnimatedNumber } from "@/components/motion/animated-number";
import { holdingHref, holdingLabel } from "@/components/portfolio/holding-items";
import { Delta, DeltaPill } from "@/components/product/delta";
import { ProductImage } from "@/components/product/product-image";
import { addDays } from "@/lib/finance/dates";
import type { HoldingView, PortfolioSummary } from "@/lib/finance/portfolio";
import { money, signedMoney, tone } from "@/lib/format";
import { useStore } from "@/lib/store/collection-store";
import { priceKey } from "@/lib/types";
import { cn } from "@/lib/utils";
import { Sparkline } from "./sparkline";

/* ------------------------------ Headline ------------------------------- */

function greeting(now = new Date()) {
  const h = now.getHours();
  return h < 5 ? "Good evening" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening";
}

function shortName(h: HoldingView) {
  const name = h.product?.name ?? "one item";
  return name.replace(/\s*\(.*?\)\s*/g, " ").replace(/\s+-\s+\d+\/\d+$/, "").trim();
}

/** Greeting plus one sentence that tells the story of today. */
export function Headline({ summary, holdings, action }: { summary: PortfolioSummary; holdings: HoldingView[]; action?: React.ReactNode }) {
  const sentence = useMemo(() => {
    const change = summary.dayChange;
    if (Math.abs(change) < 0.5) return `${summary.unitCount} items, ${money(summary.marketValue)} — a quiet day, prices held steady.`;
    const dir = change > 0 ? "up" : "down";
    const leader = [...holdings]
      .filter((h) => h.dayChange !== null && Math.sign(h.dayChange) === Math.sign(change))
      .sort((a, b) => Math.abs(b.dayChange ?? 0) - Math.abs(a.dayChange ?? 0))[0];
    return `Your collection is ${dir} ${money(Math.abs(change))} today${leader ? `, ${change > 0 ? "led" : "dragged"} by ${shortName(leader)}` : ""}.`;
  }, [summary, holdings]);

  return (
    <header className="mb-10">
      <p className="text-[13px] font-medium uppercase tracking-[0.14em] text-subtle">{greeting()}</p>
      <h1 className="mt-2 max-w-3xl text-balance text-[24px] font-semibold leading-tight tracking-[-0.02em] text-foreground/90 sm:text-[30px]">{sentence}</h1>
      {action && <div className="mt-5">{action}</div>}
    </header>
  );
}

/* ---------------------------- Metric strip ----------------------------- */

export function MetricStrip({ items }: { items: { label: string; value: React.ReactNode; sub?: React.ReactNode; href?: string }[] }) {
  return (
    <section aria-label="Key metrics" className="grid grid-cols-2 overflow-hidden rounded-[var(--radius-card)] border border-border bg-surface sm:grid-cols-4">
      {items.map((m, i) => {
        const inner = (
          <>
            <p className="text-[12px] font-medium text-muted">{m.label}</p>
            <p className="tabular mt-1.5 text-[20px] font-semibold tracking-tight sm:text-[22px]">{m.value}</p>
            {m.sub && <div className="mt-0.5 text-[12px] text-muted">{m.sub}</div>}
          </>
        );
        const cls = cn(
          "block px-5 py-4 sm:py-5",
          i % 2 === 1 && "border-l border-border",
          i >= 2 && "border-t border-border sm:border-t-0",
          i === 2 && "sm:border-l",
        );
        return m.href ? (
          <Link key={m.label} href={m.href} className={cn(cls, "transition-colors hover:bg-surface-2")}>
            {inner}
          </Link>
        ) : (
          <div key={m.label} className={cls}>
            {inner}
          </div>
        );
      })}
    </section>
  );
}

/* ------------------------------ Spotlight ------------------------------ */

function useSeries(h: HoldingView | undefined, days = 90): number[] {
  const { data, today } = useStore();
  return useMemo(() => {
    if (!h || h.identity.grade) return [];
    const key = priceKey(h.identity.productId, h.identity.printing);
    const from = addDays(today, -days);
    const pts = (data.history[key] ?? []).filter((p) => p.date >= from && p.date < today).map((p) => p.price);
    if (h.price !== null) pts.push(h.price);
    return pts;
  }, [h, data.history, today, days]);
}

function TileLabel({ icon: Icon, children, className }: { icon: React.ElementType; children: React.ReactNode; className?: string }) {
  return (
    <p className={cn("flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-[0.12em]", className)}>
      <Icon className="size-3.5" />
      {children}
    </p>
  );
}

/**
 * Editorial "bento": a large tile for the collection's star and two smaller
 * tiles for today's biggest mover and the weakest holding.
 */
export function Spotlight({ holdings }: { holdings: HoldingView[] }) {
  const star = useMemo(() => [...holdings].filter((h) => (h.unrealized ?? 0) > 0).sort((a, b) => (b.unrealized ?? 0) - (a.unrealized ?? 0))[0], [holdings]);
  const mover = useMemo(
    () => [...holdings].filter((h) => h.dayChange && h !== star).sort((a, b) => Math.abs(b.dayChange ?? 0) - Math.abs(a.dayChange ?? 0))[0],
    [holdings, star],
  );
  const laggard = useMemo(() => [...holdings].filter((h) => (h.unrealizedPct ?? 0) < 0).sort((a, b) => (a.unrealizedPct ?? 0) - (b.unrealizedPct ?? 0))[0], [holdings]);
  const series = useSeries(star);
  if (!star) return null;

  return (
    <section className="grid gap-3 lg:grid-cols-3 lg:grid-rows-2" aria-label="Spotlight">
      <Link
        href={holdingHref(star)}
        className="group relative overflow-hidden rounded-[var(--radius-card)] border border-border bg-surface p-5 transition-colors hover:bg-surface-2/60 sm:p-7 lg:col-span-2 lg:row-span-2"
      >
        <div
          aria-hidden
          className="pointer-events-none absolute -right-24 -top-24 size-[420px] rounded-full opacity-70 blur-3xl"
          style={{ background: "radial-gradient(closest-side, color-mix(in srgb, var(--up) 14%, transparent), transparent)" }}
        />
        <div className="relative flex h-full flex-col gap-6 sm:flex-row sm:items-center">
          <ProductImage
            product={star.product}
            size="lg"
            className="aspect-[16/11] w-full shrink-0 rounded-2xl transition-transform duration-700 ease-[var(--ease-apple)] group-hover:scale-[1.02] sm:aspect-square sm:w-[44%]"
          />
          <div className="flex min-w-0 flex-1 flex-col">
            <TileLabel icon={Sparkles} className="text-muted">
              Star of the collection
            </TileLabel>
            <h3 className="mt-3 line-clamp-2 text-[22px] font-semibold leading-tight tracking-[-0.01em] sm:text-[26px]">{star.product?.name}</h3>
            <p className="mt-1 truncate text-[13px] text-muted">{[star.product?.setName, holdingLabel(star)].filter(Boolean).join(" · ")}</p>
            <p className="tabular mt-5 text-[34px] font-semibold leading-none tracking-[-0.03em] text-up sm:text-[40px]">
              <AnimatedNumber value={star.unrealized ?? 0} format={signedMoney} duration={1300} />
            </p>
            <p className="tabular mt-2 text-[13px] text-muted">
              Paid {money(star.costBasis)} · worth {money(star.value)} · <Delta ratio={star.unrealizedPct} pctOnly />
            </p>
            {series.length > 2 && (
              <div className="mt-auto pt-6">
                <Sparkline values={series} tone={tone(series[series.length - 1] - series[0])} className="w-full" height={56} />
                <p className="mt-1 text-[11px] text-subtle">Last 90 days</p>
              </div>
            )}
          </div>
        </div>
      </Link>

      {mover && <MiniTile h={mover} icon={Flame} label="Biggest move today" metric={<Delta value={mover.dayChange} ratio={mover.dayChangePct} />} />}
      {laggard ? (
        <MiniTile h={laggard} icon={TrendingDown} label="Below what you paid" metric={<Delta value={laggard.unrealized} ratio={laggard.unrealizedPct} />} />
      ) : (
        <div className="flex flex-col justify-center rounded-[var(--radius-card)] border border-border bg-surface p-5">
          <TileLabel icon={TrendingDown} className="text-muted">
            Below what you paid
          </TileLabel>
          <p className="mt-3 text-[15px] font-medium">Nothing. Every holding is worth more than you paid.</p>
        </div>
      )}
    </section>
  );
}

function MiniTile({ h, icon, label, metric }: { h: HoldingView; icon: React.ElementType; label: string; metric: React.ReactNode }) {
  const series = useSeries(h, 30);
  return (
    <Link href={holdingHref(h)} className="group flex flex-col overflow-hidden rounded-[var(--radius-card)] border border-border bg-surface p-5 transition-colors hover:bg-surface-2/60">
      <TileLabel icon={icon} className="text-muted">
        {label}
      </TileLabel>
      <div className="mt-4 flex items-center gap-4">
        <ProductImage product={h.product} size="sm" className="size-16 shrink-0 rounded-xl transition-transform duration-500 group-hover:scale-105" />
        <div className="min-w-0">
          <p className="line-clamp-2 text-[15px] font-semibold leading-snug">{h.product?.name}</p>
          <p className="tabular mt-1 text-[14px]">{metric}</p>
        </div>
      </div>
      {series.length > 2 && <Sparkline values={series} tone={tone(series[series.length - 1] - series[0])} className="mt-auto w-full pt-4" height={36} />}
    </Link>
  );
}

/* -------------------------------- Shelf -------------------------------- */

/** Horizontally scrolling "shelf" of the most valuable pieces. */
export function Shelf({ holdings, title = "Your shelf", subtitle }: { holdings: HoldingView[]; title?: string; subtitle?: string }) {
  const items = useMemo(() => [...holdings].filter((h) => h.value !== null).sort((a, b) => (b.value ?? 0) - (a.value ?? 0)).slice(0, 14), [holdings]);
  if (!items.length) return null;
  return (
    <section aria-label={title}>
      <div className="mb-4 flex items-end justify-between gap-4">
        <div>
          <h2 className="text-[20px] font-semibold tracking-[-0.01em]">{title}</h2>
          {subtitle && <p className="mt-0.5 text-[13px] text-muted">{subtitle}</p>}
        </div>
        <Link href="/collection?sort=value" className="flex items-center gap-1 text-[13px] font-medium text-muted hover:text-foreground">
          See all <ArrowRight className="size-3.5" />
        </Link>
      </div>
      <div className="scrollbar-none -mx-4 flex scroll-px-4 snap-x snap-mandatory gap-4 overflow-x-auto px-4 pb-2 sm:-mx-8 sm:scroll-px-8 sm:px-8">
        {items.map((h, i) => (
          <Link key={h.key} href={holdingHref(h)} className="group w-[168px] shrink-0 snap-start sm:w-[196px]">
            <div className="relative">
              <ProductImage product={h.product} className="aspect-[4/5] w-full rounded-2xl transition-transform duration-500 ease-[var(--ease-apple)] group-hover:-translate-y-1" />
              <span className="tabular absolute left-2.5 top-2.5 flex size-6 items-center justify-center rounded-full bg-background/80 text-[11px] font-semibold backdrop-blur">{i + 1}</span>
              {h.quantity > 1 && <span className="tabular absolute right-2.5 top-2.5 rounded-full bg-background/80 px-2 py-0.5 text-[11px] font-semibold backdrop-blur">×{h.quantity}</span>}
            </div>
            <p className="mt-3 truncate text-[14px] font-medium">{h.product?.name}</p>
            <div className="mt-1 flex items-center justify-between gap-2">
              <span className="tabular text-[15px] font-semibold">{money(h.value)}</span>
              <DeltaPill ratio={h.unrealizedPct} />
            </div>
          </Link>
        ))}
      </div>
    </section>
  );
}
