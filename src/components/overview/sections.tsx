"use client";

import { ArrowRight, Flame, Sparkles, TrendingDown } from "lucide-react";
import Link from "next/link";
import { useMemo } from "react";
import { AnimatedNumber } from "@/components/motion/animated-number";
import { HoloTilt } from "@/components/motion/holo-tilt";
import { holdingHref, holdingLabel } from "@/components/portfolio/holding-items";
import { Delta, DeltaPill } from "@/components/product/delta";
import { ProductImage } from "@/components/product/product-image";
import { addDays } from "@/lib/finance/dates";
import type { HoldingView } from "@/lib/finance/portfolio";
import { money, signedMoney, tone } from "@/lib/format";
import { useStore } from "@/lib/store/collection-store";
import { priceKey } from "@/lib/types";
import { cn } from "@/lib/utils";
import { Sparkline } from "./sparkline";

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
    // A slab you valued yourself has no market trend to draw.
    if (!h || h.priceOrigin === "manual") return [];
    const key = priceKey(h.identity.productId, h.identity.printing);
    const from = addDays(today, -days);
    let pts = (data.history[key] ?? []).filter((p) => p.date >= from && p.date < today).map((p) => p.price);
    // Slabs follow their card's raw trend, scaled to the slab's price.
    const raw = data.prices[key]?.market;
    if (h.identity.grade && h.price !== null && raw) pts = pts.map((p) => (p * h.price!) / raw);
    if (h.price !== null) pts.push(h.price);
    return pts;
  }, [h, data.history, data.prices, today, days]);
}

function TileLabel({ icon: Icon, children, className }: { icon: React.ElementType; children: React.ReactNode; className?: string }) {
  return (
    <p className={cn("flex items-center gap-1.5 text-[11px] font-medium font-mono uppercase tracking-[0.06em]", className)}>
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
  const shape = star.identity.grade ? "slab" : star.product?.kind === "single" && star.product.imageUrl ? "card" : "sealed";

  return (
    <section className="grid gap-3 lg:grid-cols-3 lg:grid-rows-2" aria-label="Spotlight">
      <Link
        href={holdingHref(star)}
        className="group relative isolate overflow-hidden rounded-[var(--radius-card)] border border-border bg-surface p-5 sm:p-8 lg:col-span-2 lg:row-span-2"
      >
        <ArtGlow h={star} className="opacity-45" />
        <div className="relative flex h-full flex-col gap-7 sm:flex-row sm:items-center sm:gap-10">
          <div className="relative mx-auto w-[48%] max-w-[240px] shrink-0 sm:mx-0 sm:w-[34%]">
            {/* Soft floor shadow under the card. */}
            <div aria-hidden className="absolute inset-x-[12%] -bottom-4 h-8 rounded-[50%] bg-black/60 blur-xl" />
            <HoloTilt max={14} foil={shape === "card"} radius={shape === "slab" ? "7% / 4.4%" : shape === "card" ? "4.5% / 3.2%" : "1.5rem"} className={cn("relative w-full", shape === "slab" ? "aspect-[5/8]" : shape === "card" ? "aspect-[63/88]" : "aspect-square")}>
              <ProductImage product={star.product} grade={star.identity.grade} size="lg" frame={shape !== "card"} className={cn("h-full w-full", shape === "sealed" && "rounded-3xl")} />
            </HoloTilt>
          </div>
          <div className="flex min-w-0 flex-1 flex-col self-stretch sm:justify-center">
            <TileLabel icon={Sparkles} className="text-muted">
              Star of the collection
            </TileLabel>
            <h3 className="mt-3 line-clamp-2 text-balance text-[24px] font-semibold leading-[1.1] tracking-[-0.02em] sm:text-[30px]">{star.product?.name}</h3>
            <p className="mt-2 truncate text-[13px] text-muted">{[star.product?.setName, holdingLabel(star)].filter(Boolean).join(" · ")}</p>
            <p className="tabular mt-6 text-[40px] font-semibold leading-none tracking-[-0.035em] sm:text-[52px]">
              <span className="text-up">
                <AnimatedNumber value={star.unrealized ?? 0} format={signedMoney} duration={1300} />
              </span>
            </p>
            <dl className="mt-6 grid grid-cols-3 gap-2">
              <StarStat label="Paid" value={money(star.costBasis)} />
              <StarStat label="Worth" value={money(star.value)} />
              <StarStat label="Return" value={<Delta ratio={star.unrealizedPct} pctOnly />} />
            </dl>
            {series.length > 2 && (
              <div className="mt-6">
                <Sparkline values={series} tone={tone(series[series.length - 1] - series[0])} className="w-full" height={52} />
                <p className="mt-1 font-mono text-[10px] uppercase tracking-[0.06em] text-subtle">Last 90 days</p>
              </div>
            )}
          </div>
        </div>
      </Link>

      {mover && <MiniTile h={mover} icon={Flame} label="Biggest move today" value={mover.dayChange} ratio={mover.dayChangePct} />}
      {laggard ? (
        <MiniTile h={laggard} icon={TrendingDown} label="Below what you paid" value={laggard.unrealized} ratio={laggard.unrealizedPct} />
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

/** The product's own art, blown up and blurred into a soft backdrop. */
function ArtGlow({ h, className }: { h: HoldingView; className?: string }) {
  const src = h.product?.imageUrl;
  if (!src) return null;
  return (
    <div aria-hidden className={cn("pointer-events-none absolute inset-0 -z-10 overflow-hidden", className)}>
      {/* eslint-disable-next-line @next/next/no-img-element -- decorative blur of the product image */}
      <img src={src} alt="" className="absolute left-[-10%] top-1/2 h-[160%] w-auto max-w-none -translate-y-1/2 scale-125 opacity-80 blur-[70px] saturate-150" />
      <div className="absolute inset-0 bg-gradient-to-r from-transparent via-surface/70 to-surface" />
    </div>
  );
}

function StarStat({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="min-w-0 rounded-xl bg-background/40 px-3 py-2.5 ring-1 ring-inset ring-white/[0.06] backdrop-blur">
      <dt className="font-mono text-[10px] font-medium uppercase tracking-[0.06em] text-subtle">{label}</dt>
      <dd className="tabular mt-1 truncate text-[14px] font-semibold sm:text-[15px]">{value}</dd>
    </div>
  );
}

function MiniTile({ h, icon, label, value, ratio }: { h: HoldingView; icon: React.ElementType; label: string; value: number | null; ratio: number | null }) {
  const series = useSeries(h, 30);
  const up = (value ?? 0) >= 0;
  return (
    <Link href={holdingHref(h)} className="group relative isolate flex flex-col overflow-hidden rounded-[var(--radius-card)] border border-border bg-surface p-5">
      <ArtGlow h={h} className="opacity-25" />
      <div
        aria-hidden
        className="pointer-events-none absolute -right-16 -top-16 -z-10 size-48 rounded-full blur-3xl"
        style={{ background: `color-mix(in srgb, var(${up ? "--up" : "--down"}) 10%, transparent)` }}
      />
      <TileLabel icon={icon} className="text-muted">
        {label}
      </TileLabel>
      <div className="mt-4 flex items-center gap-4">
        <ProductImage product={h.product} grade={h.identity.grade} size="sm" className="h-20 w-16 shrink-0 transition-transform duration-500 ease-[var(--ease-apple)] group-hover:-rotate-3 group-hover:scale-105" />
        <div className="min-w-0">
          <p className="line-clamp-2 text-[14px] font-medium leading-snug text-foreground/90">{h.product?.name}</p>
          <p className="tabular mt-1.5 text-[22px] font-semibold leading-none tracking-[-0.02em]">
            <span className={up ? "text-up" : "text-down"}>{value === null ? "—" : signedMoney(value)}</span>
          </p>
          <p className="tabular mt-1 text-[12px] text-muted">
            <Delta ratio={ratio} pctOnly /> {label === "Biggest move today" ? "today" : "vs what you paid"}
          </p>
        </div>
      </div>
      {series.length > 2 && <Sparkline values={series} tone={tone(series[series.length - 1] - series[0])} className="-mx-5 -mb-5 mt-auto w-[calc(100%+2.5rem)] pt-4" height={44} />}
    </Link>
  );
}

/* -------------------------------- Shelf -------------------------------- */

/** A display shelf of the most valuable pieces: each stands on a glass ledge under its own light, with a price tag below. */
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
      <div
        className="relative overflow-hidden rounded-[var(--radius-card)] border border-border"
        // The back wall: lit from above, falling off toward the ledge.
        style={{ background: "linear-gradient(180deg, color-mix(in srgb, var(--foreground) 7%, var(--surface)), var(--surface) 55%, color-mix(in srgb, var(--background) 60%, var(--surface)))" }}
      >
        <div className="scrollbar-none overflow-x-auto">
          <div className="relative flex w-max gap-6 px-6 pb-6 pt-8 sm:gap-8 sm:px-8 sm:pb-8 sm:pt-10">
            {/* The ledge runs the full length of the scroll. */}
            <div aria-hidden className="pointer-events-none absolute inset-x-0 top-[calc(2rem+200px)] sm:top-[calc(2.5rem+236px)]">
              <div
                className="h-3"
                style={{
                  background: "linear-gradient(180deg, color-mix(in srgb, var(--foreground) 22%, transparent), color-mix(in srgb, var(--foreground) 8%, transparent))",
                  boxShadow: "inset 0 1px 0 color-mix(in srgb, var(--foreground) 40%, transparent)",
                }}
              />
              <div className="h-2" style={{ background: "color-mix(in srgb, var(--foreground) 5%, transparent)" }} />
              <div className="h-10 bg-gradient-to-b from-black/35 to-transparent" />
            </div>
            {items.map((h, i) => (
              <ShelfItem key={h.key} h={h} rank={i + 1} />
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}

function ShelfItem({ h, rank }: { h: HoldingView; rank: number }) {
  const shape = h.identity.grade ? "slab" : h.product?.kind === "single" && h.product.imageUrl ? "card" : "sealed";
  return (
    <Link href={holdingHref(h)} className="group relative flex w-[150px] shrink-0 flex-col sm:w-[176px]">
      {/* Spotlight from above. */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-10 left-1/2 h-[240px] w-[220px] -translate-x-1/2 opacity-70 transition-opacity duration-500 group-hover:opacity-100 sm:h-[280px]"
        style={{ background: "radial-gradient(50% 60% at 50% 0%, color-mix(in srgb, var(--foreground) 10%, transparent), transparent)" }}
      />
      <div className="relative flex h-[200px] items-end justify-center sm:h-[236px]">
        {/* Contact shadow where it meets the ledge. */}
        <div aria-hidden className="absolute bottom-0 left-1/2 h-3 w-[70%] -translate-x-1/2 translate-y-1/2 rounded-[50%] bg-black/60 blur-md" />
        <div className="relative flex h-full w-full items-end justify-center transition-transform duration-500 ease-[var(--ease-apple)] group-hover:-translate-y-1.5">
          {shape === "slab" ? (
            <ProductImage product={h.product} grade={h.identity.grade} size="md" className="h-full w-full items-end" />
          ) : shape === "card" ? (
            <ProductImage product={h.product} size="md" frame={false} className="h-[82%] w-full items-end" />
          ) : (
            <ProductImage product={h.product} size="md" frame={false} className="h-full w-full items-end rounded-xl" />
          )}
        </div>
        {h.quantity > 1 && (
          <span className="tabular absolute right-0 top-0 rounded-full bg-background/80 px-2 py-0.5 text-[11px] font-semibold ring-1 ring-border backdrop-blur">×{h.quantity}</span>
        )}
      </div>
      {/* Price tag hanging under the ledge. */}
      <div className="relative mt-[26px] rounded-lg bg-background/60 px-3 py-2.5 ring-1 ring-inset ring-border backdrop-blur transition-colors group-hover:bg-background/80">
        <p className="flex items-baseline gap-1.5">
          <span className="font-mono text-[10px] font-medium text-subtle">{String(rank).padStart(2, "0")}</span>
          <span className="truncate text-[13px] font-medium">{h.product?.name}</span>
        </p>
        <div className="mt-1 flex flex-wrap items-center justify-between gap-x-2 gap-y-1">
          <span className="tabular text-[14px] font-semibold">{money(h.value)}</span>
          <DeltaPill ratio={h.unrealizedPct} />
        </div>
      </div>
    </Link>
  );
}
