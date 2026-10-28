"use client";

import { ChevronLeft, ChevronRight, Play, X } from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import { createPortal } from "react-dom";
import { AnimatedNumber } from "@/components/motion/animated-number";
import { HoloTilt } from "@/components/motion/holo-tilt";
import { ProductImage } from "@/components/product/product-image";
import { addDays } from "@/lib/finance/dates";
import { acquisitionCost, effectiveTransactions } from "@/lib/finance/ledger";
import { performanceOf, type HoldingView } from "@/lib/finance/portfolio";
import { formatDate, money, signedMoney, signedPct } from "@/lib/format";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";

const SLIDE_MS = 5500;

interface Slide {
  key: string;
  bg: string;
  render: () => React.ReactNode;
}

function shortName(name: string) {
  return name.replace(/\s*\(.*?\)\s*/g, " ").replace(/\s+-\s+\d+\/\d+$/, "").trim();
}

function Kicker({ children }: { children: React.ReactNode }) {
  return <p className="text-[12px] font-medium font-mono uppercase tracking-[0.06em] text-white/60">{children}</p>;
}

function Big({ children, className }: { children: React.ReactNode; className?: string }) {
  return <p className={cn("tabular mt-3 text-[46px] font-semibold leading-[1.02] tracking-[-0.04em] text-white sm:text-[64px]", className)}>{children}</p>;
}

function ProductHero({ h }: { h: HoldingView }) {
  return (
    <HoloTilt max={14} radius="1.5rem" foil={false} className="mx-auto mt-8 aspect-square w-[62%] animate-pull-in sm:col-start-2 sm:row-span-2 sm:row-start-1 sm:mt-0 sm:w-full sm:max-w-[340px] sm:self-center">
      <ProductImage product={h.product} grade={h.identity.grade} size="lg" className="h-full w-full rounded-3xl shadow-2xl shadow-black/50" />
    </HoloTilt>
  );
}

/**
 * A slide about one product: stacked on phones (kicker, image, numbers);
 * side by side on wider screens (words left, image right).
 */
function HeroSlide({ kicker, h, children }: { kicker: string; h: HoldingView; children: React.ReactNode }) {
  return (
    <div className="flex h-full flex-col sm:grid sm:grid-cols-2 sm:grid-rows-[auto_1fr] sm:gap-x-12">
      <Kicker>{kicker}</Kicker>
      <ProductHero h={h} />
      <div className="mt-auto sm:col-start-1 sm:row-start-2 sm:self-end">{children}</div>
    </div>
  );
}

/** Builds the recap's slides from the last seven days of the collection. */
function useSlides(): { slides: Slide[]; from: string; to: string } {
  const { data, today } = useStore();
  const { holdings, summary, timeline } = usePortfolio();

  return useMemo(() => {
    const from = addDays(today, -7);
    const week = performanceOf(timeline.filter((p) => p.date >= from));
    const moved = holdings.filter((h) => h.change7dPct !== null && h.product);
    const gainer = [...moved].sort((a, b) => (b.change7dPct ?? 0) - (a.change7dPct ?? 0))[0];
    const loser = [...moved].sort((a, b) => (a.change7dPct ?? 0) - (b.change7dPct ?? 0))[0];
    const buys = effectiveTransactions(data.transactions).filter((t) => t.type === "purchase" && t.date > from && t.date <= today);
    const spent = buys.reduce((s, t) => s + acquisitionCost(t), 0);
    const units = buys.reduce((s, t) => s + t.quantity, 0);
    const best = [...holdings].filter((h) => h.unrealizedPct !== null && h.product).sort((a, b) => (b.unrealizedPct ?? 0) - (a.unrealizedPct ?? 0))[0];

    const slides: Slide[] = [];
    const gain = week?.marketGain ?? 0;
    slides.push({
      key: "intro",
      bg: "radial-gradient(120% 80% at 20% 0%, #5b3df5 0%, #1b1240 55%, #0b0b0c 100%)",
      render: () => (
        <div className="flex h-full flex-col justify-between">
          <div>
            <Kicker>Your week in Holo</Kicker>
            <p className="mt-2 text-[14px] text-white/70">
              {formatDate(addDays(from, 1))} – {formatDate(today)}
            </p>
          </div>
          <div>
            <p className="text-[18px] font-medium text-white/80">Your collection {gain >= 0 ? "grew" : "slipped"}</p>
            <Big className={gain >= 0 ? "text-[#7dffa1]" : "text-[#ff8a80]"}>
              <AnimatedNumber value={gain} format={signedMoney} duration={1400} />
            </Big>
            <p className="tabular mt-2 text-[15px] text-white/70">
              {week ? signedPct(week.twr) : "—"} from market moves alone · now {money(summary.marketValue)}
            </p>
          </div>
        </div>
      ),
    });
    if (gainer && (gainer.change7dPct ?? 0) > 0) {
      slides.push({
        key: "gainer",
        bg: "radial-gradient(120% 80% at 80% 0%, #10b981 0%, #053d2c 55%, #0b0b0c 100%)",
        render: () => (
          <HeroSlide kicker="Hottest this week" h={gainer}>
              <p className="line-clamp-2 text-[20px] font-semibold leading-tight text-white sm:text-[26px]">{shortName(gainer.product!.name)}</p>
              <Big className="text-[#7dffa1]">{signedPct((gainer.change7dPct ?? 0) / 100)}</Big>
              <p className="tabular mt-1 text-[14px] text-white/70">Now {money(gainer.price)} each</p>
          </HeroSlide>
        ),
      });
    }
    if (loser && (loser.change7dPct ?? 0) < 0) {
      slides.push({
        key: "loser",
        bg: "radial-gradient(120% 80% at 20% 0%, #e5484d 0%, #3d0f12 55%, #0b0b0c 100%)",
        render: () => (
          <HeroSlide kicker="Cooled off" h={loser}>
              <p className="line-clamp-2 text-[20px] font-semibold leading-tight text-white sm:text-[26px]">{shortName(loser.product!.name)}</p>
              <Big className="text-[#ff8a80]">{signedPct((loser.change7dPct ?? 0) / 100)}</Big>
              <p className="tabular mt-1 text-[14px] text-white/70">Now {money(loser.price)} each — buying opportunity?</p>
          </HeroSlide>
        ),
      });
    }
    slides.push({
      key: "spent",
      bg: "radial-gradient(120% 80% at 50% 0%, #f59e0b 0%, #3d2606 55%, #0b0b0c 100%)",
      render: () => (
        <div className="flex h-full flex-col justify-between">
          <Kicker>Shopping</Kicker>
          {spent > 0 ? (
            <div>
              <p className="text-[18px] font-medium text-white/80">You picked up</p>
              <Big>
                {units} item{units === 1 ? "" : "s"}
              </Big>
              <p className="tabular mt-2 text-[15px] text-white/70">{money(spent)} spent, fees included</p>
              <div className="mt-6 flex -space-x-3">
                {buys.slice(0, 5).map((t) => (
                  <ProductImage key={t.id} product={data.products[t.productId]} size="xs" className="size-14 rounded-2xl ring-2 ring-[#3d2606]" />
                ))}
              </div>
            </div>
          ) : (
            <div>
              <Big>$0 spent</Big>
              <p className="mt-3 text-[18px] text-white/80">No new buys this week.</p>
            </div>
          )}
        </div>
      ),
    });
    if (best && (best.unrealizedPct ?? 0) > 0) {
      slides.push({
        key: "best",
        bg: "radial-gradient(120% 80% at 50% 0%, #ec4899 0%, #3d0d26 55%, #0b0b0c 100%)",
        render: () => (
          <HeroSlide kicker="Best buy you’ve ever made" h={best}>
              <p className="line-clamp-2 text-[20px] font-semibold leading-tight text-white sm:text-[26px]">{shortName(best.product!.name)}</p>
              <Big className="text-[#ffb3d9]">{signedPct(best.unrealizedPct)}</Big>
              <p className="tabular mt-1 text-[14px] text-white/70">
                Paid {money(best.costBasis)} · worth {money(best.value)}
              </p>
          </HeroSlide>
        ),
      });
    }
    slides.push({
      key: "outro",
      bg: "radial-gradient(120% 80% at 50% 100%, #3b82f6 0%, #0c1d3d 55%, #0b0b0c 100%)",
      render: () => (
        <div className="flex h-full flex-col justify-between">
          <Kicker>That&apos;s a wrap</Kicker>
          <div>
            <p className="text-[18px] font-medium text-white/80">Your collection is worth</p>
            <Big>
              <AnimatedNumber value={summary.marketValue} format={money} duration={1400} />
            </Big>
            <p className="tabular mt-2 text-[15px] text-white/70">
              {summary.unitCount} items · {signedMoney(summary.unrealized)} ({signedPct(summary.unrealizedPct)}) all time
            </p>
          </div>
          <p className="text-[13px] text-white/50">See you next week.</p>
        </div>
      ),
    });
    return { slides, from, to: today };
  }, [data.transactions, data.products, holdings, summary, timeline, today]);
}

/** Story-style weekly recap: tap or use arrow keys to move, auto-advances. */
export function WeeklyRecap({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { slides } = useSlides();
  const [i, setI] = useState(0);
  const [paused, setPaused] = useState(false);

  const next = useCallback(() => setI((n) => (n + 1 < slides.length ? n + 1 : n)), [slides.length]);
  const prev = useCallback(() => setI((n) => Math.max(0, n - 1)), []);

  useEffect(() => {
    if (open) setI(0);
  }, [open]);

  useEffect(() => {
    if (!open || paused || i >= slides.length - 1) return;
    const t = window.setTimeout(next, SLIDE_MS);
    return () => window.clearTimeout(t);
  }, [open, paused, i, slides.length, next]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
      if (e.key === "ArrowRight") next();
      if (e.key === "ArrowLeft") prev();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, next, prev, onClose]);

  if (!open || typeof document === "undefined") return null;
  const slide = slides[Math.min(i, slides.length - 1)];

  return createPortal(
    <div role="dialog" aria-modal="true" aria-label="Weekly recap" className="fixed inset-0 z-[150] flex animate-fade-in items-center justify-center bg-black/85 p-4 backdrop-blur-xl" onClick={onClose}>
      <button aria-label="Close recap" onClick={onClose} className="absolute right-4 top-4 z-10 rounded-full p-2 text-white/70 hover:bg-white/10 hover:text-white">
        <X className="size-5" />
      </button>
      <button aria-label="Previous" onClick={(e) => (e.stopPropagation(), prev())} className="absolute left-4 hidden rounded-full p-3 text-white/60 hover:bg-white/10 hover:text-white disabled:opacity-0 sm:block" disabled={i === 0}>
        <ChevronLeft className="size-6" />
      </button>
      <button aria-label="Next" onClick={(e) => (e.stopPropagation(), next())} className="absolute right-4 hidden rounded-full p-3 text-white/60 hover:bg-white/10 hover:text-white disabled:opacity-0 sm:block" disabled={i >= slides.length - 1}>
        <ChevronRight className="size-6" />
      </button>

      <div
        className="relative aspect-[9/16] max-h-[88dvh] w-full max-w-[400px] select-none sm:aspect-[16/10] sm:max-h-none sm:w-[min(880px,calc(100vw-9rem),calc(88dvh*1.6))] sm:max-w-none overflow-hidden rounded-[2rem] shadow-2xl ring-1 ring-white/10"
        style={{ background: slide.bg }}
        onClick={(e) => {
          e.stopPropagation();
          const r = e.currentTarget.getBoundingClientRect();
          if (e.clientX - r.left < r.width * 0.33) prev();
          else next();
        }}
        onPointerDown={() => setPaused(true)}
        onPointerUp={() => setPaused(false)}
        onPointerLeave={() => setPaused(false)}
      >
        <div className="absolute inset-x-4 top-4 z-10 flex gap-1.5 sm:inset-x-6 sm:top-5">
          {slides.map((s, n) => (
            <div key={s.key} className="h-[3px] flex-1 overflow-hidden rounded-full bg-white/25">
              <div
                key={`${s.key}-${i}`}
                className={cn("h-full origin-left rounded-full bg-white", n < i ? "" : n > i ? "scale-x-0" : "")}
                style={n === i ? { animation: `grow-x ${SLIDE_MS}ms linear both`, animationPlayState: paused || i === slides.length - 1 ? "paused" : "running" } : undefined}
              />
            </div>
          ))}
        </div>
        <div key={slide.key} className="h-full animate-rise px-7 pb-12 pt-12 sm:px-14 sm:pb-14 sm:pt-14">
          {slide.render()}
        </div>
        <div className="pointer-events-none absolute bottom-4 left-7 text-[11px] sm:bottom-5 sm:left-14 font-semibold tracking-[0.2em] text-white/35">HOLO</div>
      </div>
    </div>,
    document.body,
  );
}

/** Pill that opens the recap, with the week's top products as avatars. */
export function RecapButton({ onClick }: { onClick: () => void }) {
  const { holdings } = usePortfolio();
  const faces = useMemo(
    () => [...holdings].filter((h) => h.change7dPct !== null).sort((a, b) => Math.abs(b.change7dPct ?? 0) - Math.abs(a.change7dPct ?? 0)).slice(0, 3),
    [holdings],
  );
  return (
    <button
      onClick={onClick}
      className="group inline-flex items-center gap-3 rounded-full border border-border bg-surface py-1.5 pl-1.5 pr-4 text-[13px] font-medium transition-colors hover:bg-surface-2"
    >
      <span className="flex -space-x-2">
        {faces.map((h) => (
          <ProductImage key={h.key} product={h.product} size="xs" className="size-7 rounded-full ring-2 ring-surface" />
        ))}
      </span>
      <span className="flex items-center gap-1.5">
        <Play className="size-3.5 fill-current" /> Your week
      </span>
    </button>
  );
}
