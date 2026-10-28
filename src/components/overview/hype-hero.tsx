"use client";

import { Play, Plus } from "lucide-react";
import Link from "next/link";
import { AnimatedNumber } from "@/components/motion/animated-number";
import { ProductImage } from "@/components/product/product-image";
import type { HoldingView, PortfolioSummary } from "@/lib/finance/portfolio";
import { money, signedMoney, signedPct } from "@/lib/format";
import { useHeroLink } from "@/lib/motion/hero";
import { useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";

/** Positions for up to five fanned cards, center first. */
const FAN = [
  { x: 0, r: 0, y: 0, z: 5, s: 1 },
  { x: -1, r: -9, y: 18, z: 4, s: 0.86 },
  { x: 1, r: 9, y: 18, z: 4, s: 0.86 },
  { x: -2, r: -17, y: 46, z: 3, s: 0.74 },
  { x: 2, r: 17, y: 46, z: 3, s: 0.74 },
];

/**
 * High-energy Overview hero: the collection's top pieces fanned out and
 * floating over a lit grid, a huge condensed headline with the value in lime,
 * and a floating action bar.
 */
export function HypeHero({ holdings, summary, onRecap }: { holdings: HoldingView[]; summary: PortfolioSummary; onRecap: () => void }) {
  const { openAdd } = useStore();
  const hero = useHeroLink();
  const top = [...holdings].filter((h) => h.product?.imageUrl && (h.value ?? 0) > 0).sort((a, b) => (b.value ?? 0) - (a.value ?? 0)).slice(0, 5);
  const allTime = summary.unrealized + summary.realized;

  return (
    <section className="relative isolate -mx-4 overflow-x-clip px-4 pb-10 pt-6 sm:-mx-8 sm:px-8 sm:pb-14 sm:pt-10" aria-label="Collection value">
      {/* Lit grid floor and drifting glows. */}
      <div aria-hidden className="hype-grid pointer-events-none absolute inset-0 -z-10" />
      <div aria-hidden className="hype-glow pointer-events-none absolute -top-24 left-1/2 -z-10 h-[520px] w-[min(900px,140vw)] rounded-full" />

      {/* Fanned card stack */}
      {top.length > 0 && (
        <div className="relative mx-auto h-[200px] w-full max-w-[560px] sm:h-[250px]">
          {top.map((h, i) => {
            const f = FAN[i];
            const href = `/product/${encodeURIComponent(h.identity.productId)}`;
            return (
              <Link
                key={h.key}
                href={href}
                onClick={(e) => hero(e, href)}
                aria-label={h.product?.name ?? "Card"}
                className="hype-card absolute left-1/2 top-0 block h-[176px] w-[126px] sm:h-[220px] sm:w-[158px]"
                style={
                  {
                    "--fx": `${f.x * 26}%`,
                    "--fx-sm": `${f.x * 30}%`,
                    "--fr": `${f.r}deg`,
                    "--fy": `${f.y}px`,
                    "--fs": f.s,
                    zIndex: f.z,
                    animationDelay: `${i * -1.1}s`,
                  } as React.CSSProperties
                }
              >
                <ProductImage
                  product={h.product}
                  grade={h.identity.grade}
                  slabKey={h.key}
                  size="md"
                  frame={h.product?.kind !== "single"}
                  className={cn("h-full w-full", h.product?.kind !== "single" && !h.identity.grade && "rounded-2xl ring-1 ring-white/10")}
                />
              </Link>
            );
          })}
        </div>
      )}

      {/* Headline */}
      <div className="relative mt-6 text-center sm:mt-8">
        <p className="font-mono text-[11px] font-medium uppercase tracking-[0.14em] text-muted">
          {summary.holdingsCount} products · {summary.unitCount} items
        </p>
        <h1 className="mt-3 font-display text-[clamp(30px,9vw,40px)] uppercase leading-[0.95] tracking-[0.005em] sm:text-[68px]">
          <span className="block">Your collection<span className="sm:hidden">&apos;s</span><span className="hidden sm:inline"> is</span> worth</span>
          <span className="tabular block text-lime drop-shadow-[0_0_28px_color-mix(in_srgb,var(--lime)_45%,transparent)]">
            <AnimatedNumber value={summary.marketValue} format={money} duration={1300} from={summary.marketValue * 0.85} />
          </span>
        </h1>
        <div className="mt-4 flex flex-wrap items-center justify-center gap-2 text-[13px]">
          <Chip label="Today">
            <Num value={summary.dayChange} /> <span className="text-subtle">{summary.dayChangePct !== null ? signedPct(summary.dayChangePct) : ""}</span>
          </Chip>
          <Chip label="All time">
            <Num value={allTime} />
          </Chip>
          <Chip label="Invested">{money(summary.costBasis)}</Chip>
        </div>
      </div>

      {/* Floating action bar */}
      <div className="relative mx-auto mt-7 flex w-full max-w-[520px] items-center gap-2 rounded-[22px] border border-white/10 bg-surface/80 p-2 shadow-2xl shadow-black/50 backdrop-blur-xl">
        <button type="button" onClick={onRecap} className="flex h-12 flex-1 items-center justify-center gap-2 rounded-2xl bg-surface-2 text-[14px] font-medium transition-colors hover:bg-surface-3">
          <Play className="size-4 fill-current" /> Your week
        </button>
        <button
          type="button"
          onClick={() => openAdd()}
          className="hype-cta flex h-12 flex-[1.4] items-center justify-center gap-2 rounded-2xl bg-lime font-display text-[17px] uppercase tracking-[0.02em] text-[#0b0b0c]"
        >
          <Plus className="size-5" strokeWidth={2.6} /> Add to collection
        </button>
      </div>
    </section>
  );
}

function Chip({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <span className="tabular inline-flex items-center gap-2 rounded-full border border-white/10 bg-surface/70 px-3 py-1.5 backdrop-blur">
      <span className="font-mono text-[10px] uppercase tracking-[0.08em] text-subtle">{label}</span>
      <span className="font-semibold">{children}</span>
    </span>
  );
}

function Num({ value }: { value: number }) {
  return <span className={value >= 0 ? "text-up" : "text-down"}>{signedMoney(value)}</span>;
}

/** Overview section heading in the display face, with a lime marker. */
export function HypeHeading({ title, subtitle, action }: { title: string; subtitle?: string; action?: React.ReactNode }) {
  return (
    <div className="mb-5 flex items-end justify-between gap-4">
      <div>
        <h2 className="flex items-center gap-2.5 font-display text-[26px] uppercase leading-none tracking-[0.01em] sm:text-[32px]">
          <span aria-hidden className="h-[0.7em] w-1.5 rounded-full bg-lime shadow-[0_0_12px_var(--lime)]" />
          {title}
        </h2>
        {subtitle && <p className="mt-1.5 text-[13px] text-muted">{subtitle}</p>}
      </div>
      {action}
    </div>
  );
}

/** A kinetic band of the collection's headline pieces scrolling past, in the display face. */
export function HypeTicker({ holdings }: { holdings: HoldingView[] }) {
  const items = [...holdings].filter((h) => (h.value ?? 0) > 0 && h.product).sort((a, b) => (b.value ?? 0) - (a.value ?? 0)).slice(0, 8);
  if (items.length < 2) return null;
  const run = (copy: number) =>
    items.map((h, i) => (
      <span key={`${copy}-${h.key}`} className="flex shrink-0 items-center gap-5 pr-5" aria-hidden={copy > 0}>
        <span className={cn("whitespace-nowrap", i % 2 ? "hype-outline" : "text-foreground")}>{h.product!.name.replace(/\s*\(.*?\)\s*/g, " ").trim()}</span>
        <span className="tabular whitespace-nowrap">
          <span className="text-foreground/90">{money(h.value)}</span>
          {h.unrealizedPct !== null && <span className={cn("ml-2", h.unrealizedPct >= 0 ? "text-up" : "text-down")}>{signedPct(h.unrealizedPct, 0)}</span>}
        </span>
        <span aria-hidden className="h-[0.5em] w-[0.5em] rotate-45 bg-lime shadow-[0_0_10px_var(--lime)]" />
      </span>
    ));
  return (
    <div className="relative -mx-4 -rotate-1 border-y border-white/10 bg-surface/60 py-3 backdrop-blur sm:-mx-8" aria-label="Top pieces">
      <div className="overflow-hidden" style={{ maskImage: "linear-gradient(90deg, transparent, black 6%, black 94%, transparent)", WebkitMaskImage: "linear-gradient(90deg, transparent, black 6%, black 94%, transparent)" }}>
        <div className="marquee-track flex w-max font-display text-[26px] uppercase leading-none tracking-[0.01em] sm:text-[34px]" style={{ ["--marquee-duration" as string]: "40s" }}>
          {run(0)}
          {run(1)}
        </div>
      </div>
    </div>
  );
}
