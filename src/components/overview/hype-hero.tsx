"use client";

import { LayoutGrid } from "lucide-react";
import Link from "next/link";
import { AnimatedNumber } from "@/components/motion/animated-number";
import { ProductImage } from "@/components/product/product-image";
import type { HoldingView, PortfolioSummary } from "@/lib/finance/portfolio";
import { money, signedMoney, signedPct } from "@/lib/format";
import { useHeroLink } from "@/lib/motion/hero";
import { cn } from "@/lib/utils";
import { looksSealed } from "@/lib/catalog";
import { useState } from "react";
import { PriceInfoDialog, type PriceInfoData } from "@/components/product/price-info";

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
export function HypeHero({
  holdings,
  summary,
  above,
  onViewCards,
}: {
  holdings: HoldingView[];
  summary: PortfolioSummary;
  /** Shown centred just above the heading (the portfolio switcher). */
  above?: React.ReactNode;
  /** The dark "View cards" button: switches Collection to Cards. */
  onViewCards?: () => void;
}) {
  const hero = useHeroLink();
  // A click on the worth: what it's made of (same as the app's Summary).
  const [info, setInfo] = useState<PriceInfoData | null>(null);
  const showBreakdown = () => {
    let market = 0, graded = 0, condition = 0, own = 0;
    for (const h of holdings) {
      const v = h.value ?? 0;
      if (h.priceStatus === "manual") own += v;
      else if (h.identity.grade) graded += v;
      else if (h.conditionEstimate) condition += v;
      else market += v;
    }
    const rows: [string, string][] = [["Market prices", money(market)]];
    if (graded > 0) rows.push(["Graded prices", money(graded)]);
    if (condition > 0) rows.push(["Estimated for condition", money(condition)]);
    if (own > 0) rows.push(["Your own values", money(own)]);
    if (summary.unpricedCount > 0) rows.push(["Without a price", `${summary.unpricedCount} not counted`]);
    setInfo({
      title: "Your collection",
      value: summary.marketValue,
      rows,
      note: "Market prices are TCGplayer's (PriceCharting where TCGplayer has none). Graded prices come from recent eBay sales of that grade, else PriceCharting, else the usual grade curve. Click any card's price for its own source.",
    });
  };
  const top = [...holdings]
    // Raw and graded cards only: sealed products stay out of the hero fan.
    .filter((h) => h.product?.imageUrl && (h.value ?? 0) > 0 && h.product.kind !== "sealed" && !looksSealed(h.product.name) && h.identity.condition !== "Sealed")
    .sort((a, b) => (b.value ?? 0) - (a.value ?? 0))
    .slice(0, 5);
  const allTime = summary.unrealized + summary.realized;

  return (
    <section
      className="relative isolate -mx-4 overflow-x-clip px-4 pb-10 pt-6 sm:-mx-8 sm:px-8 sm:pb-14 sm:pt-10 lg:pb-10 lg:pt-8"
      aria-label="Collection value"
    >
      {/* Lit grid floor and drifting glows. */}
      <div
        aria-hidden
        className="hype-grid pointer-events-none absolute inset-0 -z-10"
      />
      <div
        aria-hidden
        className="hype-glow pointer-events-none absolute -top-24 left-1/2 -z-10 h-[520px] w-[min(900px,140vw)] rounded-full"
      />

      {/* Wide screens: the value on the left, the fanned cards on the right, so the hero is
          about half as tall and more of the page sits above the fold. Phones stack them. */}
      <div className="lg:grid lg:grid-cols-[minmax(0,1.05fr)_minmax(0,1fr)] lg:items-center lg:gap-10">
        {/* Fanned card stack */}
        {top.length > 0 && (
          <div className="relative mx-auto h-[200px] w-full max-w-[560px] sm:h-[250px] lg:order-2 lg:mt-4">
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
                    className={cn(
                      "h-full w-full",
                      h.product?.kind !== "single" &&
                        !h.identity.grade &&
                        "rounded-2xl ring-1 ring-white/10",
                    )}
                  />
                </Link>
              );
            })}
          </div>
        )}

        {/* Headline: the portfolio switcher sits just above "Your collection's worth" (app's Hero). */}
        <div className="relative mt-6 text-center sm:mt-8 lg:order-1 lg:mt-0 lg:text-left">
          {above}
          <h1 className="font-display leading-[0.95]">
            <span className="block text-[clamp(22px,6.4vw,28px)] sm:text-[32px]">Your collection&apos;s worth</span>
            <span className="tabular mt-1 block text-[clamp(40px,11vw,52px)] text-lime drop-shadow-[0_0_28px_color-mix(in_srgb,var(--lime)_45%,transparent)] sm:text-[56px] lg:mt-2 lg:text-[46px] xl:text-[52px]">
              <button type="button" onClick={showBreakdown} className="tabular cursor-pointer">
                <AnimatedNumber value={summary.marketValue} format={money} duration={1300} from={summary.marketValue * 0.85} />
              </button>
            </span>
          </h1>
          <PriceInfoDialog info={info} onOpenChange={(o) => !o && setInfo(null)} />
          {/* Today / All time / Invested: one glass strip, three columns split by hairlines. */}
          <div className="glass mx-auto mt-5 flex max-w-[460px] items-center rounded-[20px] py-2.5 lg:mx-0">
            <HeroStat label="Today" tint={summary.dayChange >= 0 ? "up" : "down"} value={signedMoney(summary.dayChange)} extra={summary.dayChangePct !== null ? signedPct(summary.dayChangePct) : null} />
            <span aria-hidden className="h-[30px] w-px bg-foreground/[0.12]" />
            <HeroStat label="All time" tint={allTime >= 0 ? "up" : "down"} value={signedMoney(allTime)} />
            <span aria-hidden className="h-[30px] w-px bg-foreground/[0.12]" />
            <HeroStat label="Invested" value={money(summary.costBasis)} />
          </div>

          {onViewCards && (
            <div className="mt-6 flex justify-center lg:justify-start">
              <button
                type="button"
                onClick={onViewCards}
                className="btn-3d btn-3d-dark inline-flex h-11 items-center justify-center gap-2 rounded-2xl bg-surface-2 px-5 text-[14px] font-semibold text-foreground hover:bg-surface-3"
              >
                <LayoutGrid className="size-4" strokeWidth={2.2} /> View cards
              </button>
            </div>
          )}
        </div>
      </div>
    </section>
  );
}

function HeroStat({ label, value, extra, tint }: { label: string; value: string; extra?: string | null; tint?: "up" | "down" }) {
  const color = tint === "up" ? "text-up" : tint === "down" ? "text-down" : "text-foreground";
  return (
    <div className="flex min-w-0 flex-1 flex-col items-center gap-1 px-1.5">
      <span className="font-mono text-[10px] font-medium uppercase tracking-[0.08em] text-subtle">{label}</span>
      <span className={cn("tabular flex items-baseline gap-1 whitespace-nowrap text-[15px] font-semibold", color)}>
        {value}
        {extra && <span className={cn("rounded-md px-1.5 py-0.5 text-[11px]", tint === "down" ? "bg-down-soft" : "bg-up-soft")}>{extra}</span>}
      </span>
    </div>
  );
}

/** Overview section heading in the display face, with a lime marker. */
export function HypeHeading({
  title,
  subtitle,
  action,
}: {
  title: string;
  subtitle?: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="mb-5 flex items-end justify-between gap-4">
      <div>
        <h2 className="text-balance font-display text-[21px] leading-none sm:text-[26px]">
          {title}
        </h2>
        {subtitle && (
          <p className="mt-1.5 text-[13px] text-muted">{subtitle}</p>
        )}
      </div>
      {action}
    </div>
  );
}
