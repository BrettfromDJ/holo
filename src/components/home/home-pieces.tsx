"use client";
/* eslint-disable @next/next/no-img-element -- card art comes from the catalog's CDN */

import { ArrowRight, Check, Flame, Layers, Plus, Snowflake, Sparkles } from "lucide-react";
import Link from "next/link";
import { useEffect, useState, type CSSProperties, type ReactNode } from "react";
import { SetArt } from "@/components/explore/explore-items";
import { ProductImage } from "@/components/product/product-image";
import { withEditionArt } from "@/lib/editions";
import type { ExploreProduct, ExploreSet } from "@/lib/explore/types";
import { money } from "@/lib/format";
import { useWishlist } from "@/lib/store/wishlist";
import { cn } from "@/lib/utils";

/** A card on Home: a catalog product with, when it's one of the market's movers, its changes. */
export type HomeHit = ExploreProduct & { change24hPct?: number | null; change7dPct?: number | null };

/** The card's page, on the printing shown. */
export function hitHref(hit: Pick<ExploreProduct, "product" | "printing">): string {
  return `/product/${encodeURIComponent(hit.product.id)}${hit.printing ? `?printing=${encodeURIComponent(hit.printing)}` : ""}`;
}

/** A stored percent (12.5 = +12.5%) as signed text with a real minus sign. */
export function pctText(pct: number | null | undefined): string {
  if (pct === null || pct === undefined || !Number.isFinite(pct)) return "—";
  const v = Math.abs(pct) >= 10 ? Math.abs(pct).toFixed(0) : Math.abs(pct).toFixed(1);
  return `${pct >= 0 ? "+" : "−"}${v}%`;
}

const pictured = (hit: HomeHit) => withEditionArt(hit.product, hit.printing);

/** Hide a scroll row's bar on every browser. */
const NO_BAR = "[scrollbar-width:none] [&::-webkit-scrollbar]:hidden";

// MARK: Rows

/** A row's title: display 22, no subtitle, no icon, no line, no arrow; "New" for this week's ideas. */
export function RowTitle({ title, fresh, link }: { title: string; fresh?: boolean; link?: ReactNode }) {
  return (
    <div className="mb-3 flex items-center gap-2">
      <h2 className="min-w-0 truncate font-display text-[22px] leading-[1.1] tracking-[-0.03em]">{title}</h2>
      {fresh && <span className="tag-skew tag-lime">New</span>}
      <span className="flex-1" />
      {link}
    </div>
  );
}

/** A quiet "Calendar →" link beside a row's title. */
export function SeeAll({ href, label }: { href: string; label: string }) {
  return (
    <Link href={href} className="flex shrink-0 items-center gap-1 text-[13px] font-medium text-muted hover:text-foreground">
      {label} <ArrowRight className="size-3.5" />
    </Link>
  );
}

/** A row that scrolls sideways inside the page's margins, fading on the right while there's more. */
export function ScrollRow({ children, className, gap = "gap-2.5" }: { children: ReactNode; className?: string; gap?: string }) {
  return (
    <div className={cn("fade-row overflow-x-auto overscroll-x-contain", NO_BAR, className)}>
      <div className={cn("flex w-max", gap)}>{children}</div>
    </div>
  );
}

/** One card in a row: 150×209 art with its price (and a move, for Top 10) on a painted pill. */
export function Poster({ hit, change, className }: { hit: HomeHit; change?: number | null; className?: string }) {
  const p = pictured(hit);
  return (
    <Link href={hitHref(hit)} className={cn("group relative block h-[209px] w-[150px] shrink-0", className)} aria-label={`${hit.product.name}${hit.market !== null ? `, ${money(hit.market)}` : ""}`}>
      <ProductImage product={p} size="md" className="h-full w-full transition-transform duration-300 ease-[var(--ease-apple)] group-hover:-translate-y-1" />
      {hit.market !== null && (
        <span className="tabular absolute bottom-2 left-2 flex items-center gap-1.5 rounded-full bg-black/60 px-[9px] py-[5px] text-[13px] font-semibold leading-none text-white shadow-[0_1px_2px_rgb(0_0_0/0.35)] ring-1 ring-white/15">
          {money(hit.market)}
          {change !== undefined && change !== null && <span className={change >= 0 ? "text-[var(--lime)]" : "text-[var(--plan-pink)]"}>{pctText(change)}</span>}
        </span>
      )}
    </Link>
  );
}

/** Every card, big, all one size, in a row you scroll. */
export function PosterRow({ hits }: { hits: HomeHit[] }) {
  return (
    <ScrollRow>
      {hits.map((h) => (
        <Poster key={`${h.product.id}|${h.printing ?? ""}`} hit={h} />
      ))}
    </ScrollRow>
  );
}

/** A themed collection: its title, then every card in it. */
export function ThemeRow({ title, fresh, hits, label }: { title: string; fresh?: boolean; hits: HomeHit[]; label?: string }) {
  return (
    <section>
      {label && <p className="mb-1 font-mono text-[11px] uppercase tracking-[0.1em] text-[var(--lime)]">{label}</p>}
      <RowTitle title={title} fresh={fresh} />
      <PosterRow hits={hits} />
    </section>
  );
}

// MARK: Chips

/** Streaming-style category tabs: separate glass tiles, the picked one filled white. */
export function ChipTabs<T extends string>({ options, value, onChange, label }: { options: { id: T; label: string }[]; value: T; onChange: (v: T) => void; label: string }) {
  return (
    <div role="tablist" aria-label={label} className={cn("fade-row overflow-x-auto", NO_BAR)}>
      <div className="flex w-max gap-2">
        {options.map((o) => {
          const on = o.id === value;
          return (
            <button
              key={o.id}
              type="button"
              role="tab"
              aria-selected={on}
              onClick={() => onChange(o.id)}
              className={cn(
                "h-9 rounded-[13px] px-4 text-[14px] font-medium transition-colors",
                on ? "bg-[#f5f5f7] text-[#0b0b0c]" : "border border-white/12 bg-white/[0.06] text-white shadow-[inset_0_1px_0_rgb(255_255_255/0.08)] backdrop-blur-xl hover:bg-white/10",
              )}
            >
              {o.label}
            </button>
          );
        })}
      </div>
    </div>
  );
}

// MARK: Card of the day

/** Home's lead: the card big on its own blurred art, its name, one line and two buttons. */
export function CardOfTheDay({ hit, kind }: { hit: HomeHit; kind: "day" | "week" | { topPull: string } }) {
  const p = pictured(hit);
  const pct = kind === "day" ? hit.change24hPct : kind === "week" ? hit.change7dPct : null;
  const tag = kind === "day" ? "Card of the day" : kind === "week" ? "Card of the week" : "Top pull";
  const down = (pct ?? 0) < 0;
  const tone = down ? "var(--plan-pink)" : "var(--lime)";
  const href = hitHref(hit);
  return (
    <section className="relative isolate overflow-hidden rounded-[24px] border border-white/12 bg-[#080808]">
      {p.imageUrl && <img src={p.imageUrl} alt="" aria-hidden className="absolute inset-0 -z-10 h-full w-full scale-[1.4] object-cover opacity-45 blur-[40px]" />}
      <div aria-hidden className="absolute inset-0 -z-10 bg-[linear-gradient(to_bottom,rgb(0_0_0/0.05),rgb(0_0_0/0.5),rgb(0_0_0/0.92))]" />
      <span className={cn("tag-skew absolute left-4 top-4 z-10", down ? "tag-pink" : "tag-lime")}>{tag}</span>
      <Link href={href} className="relative flex justify-center pb-6 pt-12">
        <span aria-hidden className="absolute inset-0" style={{ background: `radial-gradient(200px 200px at 50% 50%, color-mix(in srgb, ${tone} 30%, transparent), transparent)` }} />
        <ProductImage product={p} size="lg" priority className="relative h-[330px] w-[236px] shadow-[0_14px_48px_rgb(0_0_0/0.6)]" />
      </Link>
      <div className="flex flex-col items-center gap-2.5 px-[18px] pb-[18px] text-center">
        <h2 className="line-clamp-2 text-balance font-display text-[30px] leading-[1.05] tracking-[-0.033em]">{p.name}</h2>
        <p className="text-[14px] text-muted">
          {p.setName}
          {pct !== null && pct !== undefined && (
            <span className="font-semibold" style={{ color: tone }}>
              {p.setName ? "  •  " : ""}
              {pctText(pct)}
            </span>
          )}
        </p>
        <div className="mt-2 flex w-full max-w-[420px] gap-2.5">
          <Link href={href} className="btn-3d btn-3d-light flex h-12 flex-1 items-center justify-center gap-2 rounded-[14px] bg-[#f5f5f7] text-[16px] font-semibold text-[#0b0b0c]">
            <Layers className="size-4" /> View card
          </Link>
          <WishButton hit={hit} />
        </div>
      </div>
    </section>
  );
}

/** "+ Wishlist", or "On wishlist" once it's there (tap again to take it off). */
function WishButton({ hit }: { hit: HomeHit }) {
  const { has, add, remove } = useWishlist();
  const on = has(hit.product.id);
  return (
    <button
      type="button"
      aria-pressed={on}
      onClick={() => (on ? remove(hit.product.id) : add(hit.product, hit.market, { printing: hit.printing }))}
      className="btn-3d btn-3d-dark flex h-12 flex-1 items-center justify-center gap-2 rounded-[14px] bg-surface-2 text-[16px] font-semibold text-white"
    >
      {on ? <Check className="size-4" /> : <Plus className="size-4" />} {on ? "On wishlist" : "Wishlist"}
    </button>
  );
}

// MARK: Heating up / Cooling off

function useReducedMotion() {
  const [reduced, setReduced] = useState(false);
  useEffect(() => {
    const m = window.matchMedia("(prefers-reduced-motion: reduce)");
    setReduced(m.matches);
    const on = () => setReduced(m.matches);
    m.addEventListener("change", on);
    return () => m.removeEventListener("change", on);
  }, []);
  return reduced;
}

/** The week's top risers (fire) or biggest fallers (ice), cycling five cards about every four seconds. */
export function HotColdTile({ hits, hot, className }: { hits: HomeHit[]; hot: boolean; className?: string }) {
  const [index, setIndex] = useState(0);
  const reduced = useReducedMotion();
  useEffect(() => {
    if (reduced || hits.length < 2) return;
    let interval: ReturnType<typeof setInterval> | undefined;
    // The cold tile starts later so the two don't change at the same moment.
    const start = setTimeout(() => {
      setIndex((i) => i + 1);
      interval = setInterval(() => !document.hidden && setIndex((i) => i + 1), 4000);
    }, hot ? 4000 : 6000);
    return () => {
      clearTimeout(start);
      if (interval) clearInterval(interval);
    };
  }, [reduced, hits.length, hot]);
  if (!hits.length) return null;
  const at = index % hits.length;
  const hit = hits[at];
  const glow = hot ? "#FF7A1A" : "#7DD3FC";
  const Icon = hot ? Flame : Snowflake;
  return (
    <Link
      href={hitHref(hit)}
      className={cn("relative flex min-w-0 flex-col gap-2.5 overflow-hidden rounded-[22px] bg-[#080808] p-3.5 text-white", className)}
      style={{ border: `1px solid color-mix(in srgb, ${glow} 35%, transparent)`, backgroundImage: `radial-gradient(130px 130px at 50% 42%, color-mix(in srgb, ${glow} 32%, transparent), transparent)` }}
    >
      <div className="flex items-center gap-[5px]">
        <Icon className="size-[11px]" style={{ color: glow }} />
        <span className="font-mono text-[10px] uppercase tracking-[0.12em] text-white/80">{hot ? "Heating up" : "Cooling off"}</span>
        <span className="flex-1" />
        {hits.length > 1 && (
          <span className="flex gap-[3px]" aria-hidden>
            {hits.map((h, i) => (
              <span key={h.product.id} className="size-1 rounded-full" style={{ background: i === at ? glow : "rgb(255 255 255 / 0.25)" }} />
            ))}
          </span>
        )}
      </div>
      <div key={hit.product.id} className="flex flex-1 flex-col gap-2.5 animate-fade-in">
        <div className="flex justify-center py-1">
          <div style={{ transform: `rotate(${hot ? -6 : 6}deg)`, filter: `drop-shadow(0 0 16px color-mix(in srgb, ${glow} 55%, transparent))` }}>
            <ProductImage product={pictured(hit)} size="sm" className="h-[117px] w-[84px]" />
          </div>
        </div>
        <p className="truncate text-[13px] font-medium">{hit.product.name}</p>
        <div className="flex items-baseline justify-between gap-1">
          <span className="tabular truncate font-display text-[17px] tracking-[-0.025em]">{money(hit.market)}</span>
          <span className="tabular shrink-0 font-display text-[17px] tracking-[-0.025em]" style={{ color: (hit.change7dPct ?? 0) >= 0 ? "var(--lime)" : "var(--plan-pink)" }}>
            {pctText(hit.change7dPct)}
          </span>
        </div>
      </div>
    </Link>
  );
}

// MARK: Top 10

/** Netflix-style Top 10: each card in front of its rank as a huge outlined numeral. */
export function TopTenRow({ hits }: { hits: HomeHit[] }) {
  return (
    <ScrollRow gap="gap-3.5">
      {hits.map((h, i) => {
        const rank = i + 1;
        return (
          <div key={h.product.id} className="flex items-end">
            <span
              aria-hidden
              className="pointer-events-none flex h-[209px] select-none items-end overflow-hidden"
              style={{ marginRight: rank >= 10 ? -34 : -26 }}
            >
              <span
                className="block font-display text-[180px] font-semibold leading-[0.74]"
                style={{ letterSpacing: "-12px", color: "var(--background)", WebkitTextStroke: "3px rgb(255 255 255 / 0.55)", paintOrder: "stroke fill" } as CSSProperties}
              >
                {rank}
              </span>
            </span>
            <div className="relative rounded-lg shadow-[-4px_4px_20px_rgb(0_0_0/0.6)]">
              <span className="sr-only">Number {rank}: </span>
              <Poster hit={h} change={h.change7dPct} />
            </div>
          </div>
        );
      })}
    </ScrollRow>
  );
}

// MARK: Newest set

/** The newest set on stage: its art behind, its chase cards fanned out, the top pull's price. */
export function SetShowcase({ set, hits }: { set: ExploreSet; hits: HomeHit[] }) {
  const top = hits[0];
  // Ranks laid out so the top pull sits in the middle: 3, 1, 0, 2, 4 for five cards.
  const ranked = hits.map((hit, rank) => ({ rank, hit }));
  const left: typeof ranked = [];
  const right: typeof ranked = [];
  for (const item of ranked.slice(1)) {
    if (item.rank % 2 === 1) left.unshift(item);
    else right.push(item);
  }
  const order = [...left, ...ranked.slice(0, 1), ...right];
  const mid = (order.length - 1) / 2;
  return (
    <Link href={`/explore/${encodeURIComponent(set.slug)}`} className="relative isolate block overflow-hidden rounded-[26px] border border-white/10 bg-[#070707] p-5 text-white">
      <div aria-hidden className="absolute inset-0 -z-10 opacity-45 blur-[14px]">
        <SetArt set={set} className="h-full w-full" />
      </div>
      <div
        aria-hidden
        className="absolute inset-0 -z-10"
        style={{ backgroundImage: "radial-gradient(220px 220px at 50% 70%, color-mix(in srgb, var(--plan-blue) 28%, transparent), transparent), linear-gradient(to bottom, rgb(0 0 0 / 0.75), rgb(0 0 0 / 0.35), rgb(0 0 0 / 0.8))" }}
      />
      <div className="space-y-1.5">
        <span className="tag-skew tag-blue">
          <Sparkles className="size-3" /> Newest set
        </span>
        <h2 className="line-clamp-2 text-balance font-display text-[26px] leading-[1.1] tracking-[-0.027em]">Chasing in {set.name}</h2>
        {top && (
          <p className="truncate text-[13px] text-white/75">
            Top pull {money(top.market)} · {top.product.name}
          </p>
        )}
      </div>
      <div className="relative mx-auto mt-4 h-[190px] w-full max-w-[360px]">
        {order.map((item, slot) => {
          const offset = slot - mid;
          const lift = Math.abs(offset) * 10 - (item.rank === 0 ? 10 : 0);
          return (
            <div
              key={item.hit.product.id}
              className="absolute bottom-[26px] left-1/2 -ml-[46px] h-[128px] w-[92px] origin-bottom"
              style={{ transform: `translate(${offset * 46}px, ${lift}px) rotate(${offset * 9}deg)`, zIndex: item.rank === 0 ? 10 : 5 - Math.abs(offset) }}
            >
              <ProductImage product={pictured(item.hit)} size="sm" className="h-full w-full shadow-[0_6px_20px_rgb(0_0_0/0.55)]" />
            </div>
          );
        })}
      </div>
      <p className="mt-4 flex items-center gap-1.5 text-[14px] font-semibold text-[var(--lime)]">
        See the set <ArrowRight className="size-3.5" />
      </p>
    </Link>
  );
}

// MARK: Hot sealed

/** Hot sealed: each product standing in its well, its rise as a lime tag. */
export function HotSealedRow({ hits }: { hits: HomeHit[] }) {
  return (
    <ScrollRow gap="gap-3">
      {hits.map((h) => (
        <Link key={h.product.id} href={hitHref(h)} className="group w-[160px] shrink-0">
          <div className="relative">
            <ProductImage product={h.product} size="md" className="size-[160px] rounded-[22px] transition-transform duration-300 group-hover:-translate-y-1" />
            {h.change7dPct !== null && h.change7dPct !== undefined && h.change7dPct > 0 && <span className="tag-skew tag-lime absolute left-2.5 top-2.5">{pctText(h.change7dPct)}</span>}
          </div>
          <p className="mt-2 line-clamp-2 text-[13px] font-medium leading-snug">{h.product.name}</p>
          <p className="tabular mt-1 font-display text-[17px] leading-none tracking-[-0.025em]">{money(h.market)}</p>
        </Link>
      ))}
    </ScrollRow>
  );
}

// MARK: Placeholders

/** A row of cards still on its way: a short title bar and card shapes, still. */
export function PlaceholderRow() {
  return (
    <div aria-hidden className="pointer-events-none">
      <div className="mb-3.5 h-5 w-[170px] rounded-md bg-white/[0.07]" />
      <div className="flex gap-3 overflow-hidden">
        {Array.from({ length: 6 }, (_, i) => (
          <div key={i} className="h-[209px] w-[150px] shrink-0 rounded-xl bg-white/[0.05]" />
        ))}
      </div>
    </div>
  );
}
