"use client";

import { ArrowRight, ArrowUpRight, CalendarDays, Plus } from "lucide-react";
import Link from "next/link";
import { useMemo, useState } from "react";
import { holdingHref } from "@/components/portfolio/holding-items";
import { Delta } from "@/components/product/delta";
import { ProductImage } from "@/components/product/product-image";
import { addDays, daysBetween } from "@/lib/finance/dates";
import { acquisitionCost } from "@/lib/finance/ledger";
import type { HoldingView } from "@/lib/finance/portfolio";
import { formatDate, money, signedMoney, signedPct } from "@/lib/format";
import { useStore } from "@/lib/store/collection-store";
import { priceKey } from "@/lib/types";
import { cn } from "@/lib/utils";
import { Sparkline } from "./sparkline";

/**
 * Five takes on the Overview "Recently added" box, for comparison on /lab/activity.
 * Each takes the five most recently added holdings.
 */

function Heading({ title = "Recently added", tone = "light" }: { title?: string; tone?: "light" | "dark" }) {
  return (
    <div className="mb-5 flex items-center justify-between gap-3">
      <h2 className="flex items-center gap-2.5 font-display text-[24px] uppercase leading-none tracking-[0.01em] sm:text-[28px]">
        <span aria-hidden className={cn("h-[0.7em] w-1.5 rounded-full", tone === "light" ? "bg-lime shadow-[0_0_12px_var(--lime)]" : "bg-[#0b0b0c]")} />
        {title}
      </h2>
      <Link href="/activity" className={cn("flex items-center gap-1 text-[13px] font-medium", tone === "light" ? "text-muted hover:text-foreground" : "text-black/55 hover:text-black")}>
        Activity <ArrowRight className="size-3.5" />
      </Link>
    </div>
  );
}

const gainOf = (h: HoldingView) => (h.value === null ? null : h.value - h.costBasis);

/* ------------------------------ A. Filmstrip ------------------------------ */

/** Big card art in a row, newest first, each with its date and how it's done since. */
export function ActivityFilmstrip({ holdings }: { holdings: HoldingView[] }) {
  return (
    <div className="tint tint-blue hype-surface min-w-0 rounded-[var(--radius-card)] p-6 sm:p-7">
      <Heading />
      <ol className="-mx-6 flex snap-x gap-4 overflow-x-auto px-6 pb-2 sm:-mx-7 sm:px-7 lg:grid lg:grid-cols-5 lg:overflow-visible">
        {holdings.map((h, i) => {
          const up = (h.unrealizedPct ?? 0) >= 0;
          return (
            <li key={h.key} className="w-[42vw] max-w-[200px] shrink-0 snap-start lg:w-auto lg:max-w-none">
              <Link href={holdingHref(h)} className="group block">
                <div className="relative">
                  <ProductImage product={h.product} grade={h.identity.grade} slabKey={h.key} size="md" frame={h.product?.kind !== "single"} className="aspect-[5/7] w-full rounded-2xl transition-transform duration-500 ease-[var(--ease-apple)] group-hover:-translate-y-1.5 group-hover:-rotate-1" />
                  <span className="absolute left-2 top-2 rounded-full bg-background/85 px-2 py-0.5 font-mono text-[10px] uppercase tracking-[0.06em] text-foreground/80 ring-1 ring-white/10 backdrop-blur">
                    {i === 0 ? "Newest" : formatDate(h.lastAcquired)}
                  </span>
                  {h.unrealizedPct !== null && <span className={cn("tag-skew absolute -bottom-2 right-2", up ? "tag-lime" : "tag-pink")}>{signedPct(h.unrealizedPct, 0)}</span>}
                </div>
                <p className="mt-4 line-clamp-1 text-[13px] font-medium">{h.product?.name}</p>
                <p className="hype-num tabular text-[17px]">{money(h.value)}</p>
              </Link>
            </li>
          );
        })}
      </ol>
    </div>
  );
}

/* ------------------------------- B. Receipt ------------------------------- */

/** A printed receipt: dotted leaders, a running total, and a barcode. */
export function ActivityReceipt({ holdings }: { holdings: HoldingView[] }) {
  const paid = holdings.reduce((s, h) => s + h.costBasis, 0);
  const worth = holdings.reduce((s, h) => s + (h.value ?? 0), 0);
  return (
    <div className="mx-auto w-full max-w-[560px]">
      <div className="receipt relative rounded-t-2xl bg-[#f4f4ef] px-6 pb-10 pt-6 text-[#0b0b0c] shadow-[0_30px_60px_-30px_rgb(212_255_58/0.45)] sm:px-8">
        <Heading tone="dark" />
        <p className="text-center font-mono text-[11px] uppercase tracking-[0.2em] text-black/50">Holo · collection receipt</p>
        <ol className="mt-5 space-y-3 border-y border-dashed border-black/25 py-5 font-mono text-[13px]">
          {holdings.map((h) => (
            <li key={h.key}>
              <Link href={holdingHref(h)} className="group flex items-baseline gap-2">
                <span className="truncate font-semibold group-hover:underline">{h.product?.name}</span>
                <span aria-hidden className="min-w-6 flex-1 translate-y-[-3px] border-b-2 border-dotted border-black/25" />
                <span className="tabular shrink-0">{money(h.costBasis)}</span>
              </Link>
              <p className="flex justify-between text-[11px] text-black/50">
                <span>
                  {formatDate(h.lastAcquired)} · qty {h.quantity}
                </span>
                <span className="tabular">now {money(h.value)}</span>
              </p>
            </li>
          ))}
        </ol>
        <dl className="mt-4 space-y-1 font-mono text-[13px]">
          <div className="flex justify-between">
            <dt className="text-black/55">Paid</dt>
            <dd className="tabular">{money(paid)}</dd>
          </div>
          <div className="flex justify-between text-[16px] font-bold">
            <dt>Worth today</dt>
            <dd className="tabular">{money(worth)}</dd>
          </div>
          <div className="flex justify-between">
            <dt className="text-black/55">Since</dt>
            <dd className={cn("tabular rounded px-1.5 font-bold", worth >= paid ? "bg-[#0b0b0c] text-[var(--lime)]" : "bg-[#0b0b0c] text-[var(--down)]")}>{signedMoney(worth - paid)}</dd>
          </div>
        </dl>
        <div aria-hidden className="barcode mx-auto mt-6 h-10 w-3/4" />
      </div>
    </div>
  );
}

/* ------------------------------ C. Calendar ------------------------------- */

const WEEKS = 26;

const ago = (d: number) => (d === 0 ? "Today" : d === 1 ? "Yesterday" : d < 60 ? `${d} days ago` : `${Math.round(d / 30)} months ago`);

/** Six months of buying as a heat grid, with the latest adds beside it. */
export function ActivityCalendar({ holdings }: { holdings: HoldingView[] }) {
  const { data, today } = useStore();
  const { cells, total, days } = useMemo(() => {
    const spend = new Map<string, number>();
    for (const t of data.transactions) if (t.type === "purchase" || (t.type === "adjustment" && t.quantity > 0)) spend.set(t.date, (spend.get(t.date) ?? 0) + acquisitionCost(t));
    // Columns are weeks ending on today's weekday.
    const start = addDays(today, -(WEEKS * 7 - 1));
    const cells = Array.from({ length: WEEKS * 7 }, (_, i) => {
      const date = addDays(start, i);
      return { date, v: spend.get(date) ?? 0 };
    });
    const total = cells.reduce((s, c) => s + c.v, 0);
    return { cells, total, days: cells.filter((c) => c.v > 0).length };
  }, [data.transactions, today]);
  const max = Math.max(1, ...cells.map((c) => c.v));

  return (
    <div className="tint tint-lime hype-surface min-w-0 rounded-[var(--radius-card)] p-6 sm:p-7">
      <Heading />
      <div className="grid gap-8 lg:grid-cols-[auto_minmax(0,1fr)]">
        <div>
          <div className="grid grid-flow-col grid-rows-7 gap-[3px] sm:gap-1" role="img" aria-label={`Added on ${days} days in the last ${WEEKS} weeks`}>
            {cells.map((c) => (
              <span
                key={c.date}
                title={c.v ? `${formatDate(c.date)} · ${money(c.v)}` : formatDate(c.date)}
                className="size-2 rounded-[2px] sm:size-[13px] sm:rounded-[3px]"
                style={{ background: c.v ? `color-mix(in srgb, var(--lime) ${25 + Math.round((c.v / max) * 75)}%, transparent)` : "color-mix(in srgb, var(--foreground) 6%, transparent)", boxShadow: c.v / max > 0.6 ? "0 0 10px color-mix(in srgb, var(--lime) 60%, transparent)" : undefined }}
              />
            ))}
          </div>
          <p className="mt-4 flex items-center gap-2 font-mono text-[11px] uppercase tracking-[0.06em] text-subtle">
            <CalendarDays className="size-3.5" /> {days} buying days · <span className="text-foreground">{money(total)}</span> in 6 months
          </p>
        </div>
        <ol className="min-w-0 divide-y divide-white/[0.06]">
          {holdings.map((h) => (
            <li key={h.key}>
              <Link href={holdingHref(h)} className="group flex items-center gap-3 py-2.5">
                <ProductImage product={h.product} size="xs" className="size-10 shrink-0 rounded-lg" />
                <div className="min-w-0 flex-1">
                  <p className="truncate text-[14px] font-medium">{h.product?.name}</p>
                  <p className="font-mono text-[10px] uppercase tracking-[0.06em] text-subtle">{h.lastAcquired ? ago(daysBetween(h.lastAcquired, today)) : "—"}</p>
                </div>
                <div className="text-right">
                  <p className="hype-num tabular text-[15px]">{money(h.value)}</p>
                  <Delta ratio={h.unrealizedPct} pctOnly className="text-[12px]" />
                </div>
              </Link>
            </li>
          ))}
        </ol>
      </div>
    </div>
  );
}

/* ------------------------------- D. Ticker -------------------------------- */

/** Editorial list in the display face; hovering a row floats its card art in. */
export function ActivityTicker({ holdings }: { holdings: HoldingView[] }) {
  const [hover, setHover] = useState<string | null>(null);
  return (
    <div className="tint tint-pink hype-surface relative min-w-0 overflow-hidden rounded-[var(--radius-card)] p-6 sm:p-7">
      <Heading />
      <ol>
        {holdings.map((h, i) => {
          const g = gainOf(h);
          return (
            <li key={h.key} className="border-t border-white/[0.08] first:border-t-0">
              <Link
                href={holdingHref(h)}
                onMouseEnter={() => setHover(h.key)}
                onMouseLeave={() => setHover(null)}
                className="group relative flex items-center gap-4 py-3.5"
              >
                <span className="w-7 shrink-0 font-mono text-[11px] text-subtle">0{i + 1}</span>
                <span className="min-w-0 flex-1 truncate font-display text-[19px] uppercase leading-none tracking-[0.01em] transition-transform duration-300 ease-[var(--ease-apple)] group-hover:translate-x-2 sm:text-[30px]">
                  {h.product?.name}
                </span>
                <span className="hidden shrink-0 font-mono text-[11px] uppercase tracking-[0.06em] text-subtle sm:block">{formatDate(h.lastAcquired)}</span>
                <span className={cn("hype-num tabular w-24 shrink-0 text-right text-[17px] sm:text-[20px]", g === null ? "text-subtle" : g >= 0 ? "text-up" : "text-down")}>{g === null ? "—" : signedMoney(g)}</span>
                <ProductImage
                  product={h.product}
                  size="sm"
                  className={cn(
                    "pointer-events-none absolute right-36 top-1/2 z-10 hidden h-28 w-20 -translate-y-1/2 rotate-6 rounded-xl shadow-2xl shadow-black/60 transition-all duration-300 ease-[var(--ease-apple)] lg:block",
                    hover === h.key ? "scale-100 opacity-100" : "scale-75 opacity-0",
                  )}
                />
              </Link>
            </li>
          );
        })}
      </ol>
    </div>
  );
}

/* -------------------------------- E. Deck --------------------------------- */

/** The newest piece up front with its story; older ones stacked beside it, tap to bring one forward. */
export function ActivityDeck({ holdings }: { holdings: HoldingView[] }) {
  const { today } = useStore();
  const [sel, setSel] = useState(0);
  const h = holdings[Math.min(sel, holdings.length - 1)];
  if (!h) return null;
  const g = gainOf(h);
  const held = h.lastAcquired ? daysBetween(h.lastAcquired, today) : null;
  return (
    <div className="plan plan-blue min-w-0 overflow-hidden rounded-[var(--radius-card)] p-6 sm:p-7">
      <Heading />
      <div className="grid items-center gap-8 md:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)_auto]">
        <div key={h.key} className="animate-rise mx-auto w-[180px] md:w-full md:max-w-[220px]">
          <ProductImage product={h.product} grade={h.identity.grade} slabKey={h.key} size="lg" frame={h.product?.kind !== "single"} className="aspect-[5/7] w-full rounded-2xl shadow-2xl shadow-black/50" />
        </div>
        <div key={`${h.key}-t`} className="animate-rise min-w-0">
          <span className="tag-skew tag-white">{sel === 0 ? "Just added" : formatDate(h.lastAcquired)}</span>
          <h3 className="mt-3 line-clamp-2 font-display text-[30px] uppercase leading-[0.98] tracking-[0.01em] sm:text-[38px]">{h.product?.name}</h3>
          <p className="mt-1 truncate text-[13px] text-muted">{h.product?.setName}</p>
          <p className={cn("hype-num tabular mt-5 text-[40px] leading-none", g === null ? "" : g >= 0 ? "text-up" : "text-down")}>{g === null ? money(h.value) : signedMoney(g)}</p>
          <p className="mt-2 text-[13px] text-muted">
            {held === null ? "" : held === 0 ? "Added today" : `In ${held} day${held === 1 ? "" : "s"}`} · paid {money(h.costBasis)}
          </p>
          <Link href={holdingHref(h)} className="mt-5 inline-flex items-center gap-1.5 text-[13px] font-medium text-foreground/80 hover:text-foreground">
            Open <ArrowUpRight className="size-3.5" />
          </Link>
        </div>
        <ol className="flex gap-3 md:flex-col">
          {holdings.map((x, i) => (
            <li key={x.key}>
              <button
                type="button"
                onClick={() => setSel(i)}
                aria-label={x.product?.name ?? "Holding"}
                aria-pressed={i === sel}
                className={cn("block rounded-xl transition-all duration-300 ease-[var(--ease-apple)]", i === sel ? "ring-2 ring-[var(--lime)] ring-offset-2 ring-offset-[var(--surface)]" : "opacity-50 hover:opacity-100")}
              >
                <ProductImage product={x.product} size="xs" className="h-14 w-10 rounded-lg" />
              </button>
            </li>
          ))}
        </ol>
      </div>
    </div>
  );
}

/* ----------------------------- F. Binder page ----------------------------- */

/** A nine-pocket binder page: plastic sleeves with a sheen, ring holes, and a price sticker on each pocket. */
export function ActivityBinder({ holdings }: { holdings: HoldingView[] }) {
  const { openAdd } = useStore();
  return (
    <div className="tint tint-azure hype-surface min-w-0 rounded-[var(--radius-card)] p-6 sm:p-7">
      <Heading />
      <div className="relative rounded-2xl bg-[#0d0d10] p-3 pl-10 ring-1 ring-white/[0.06] sm:p-4 sm:pl-12">
        {/* Ring holes */}
        <div aria-hidden className="absolute inset-y-0 left-3 flex flex-col justify-around sm:left-4">
          {[0, 1, 2].map((i) => (
            <span key={i} className="size-3.5 rounded-full bg-background shadow-[inset_0_1px_2px_rgb(0_0_0/0.8)] ring-1 ring-white/10" />
          ))}
        </div>
        <ol className="grid grid-cols-3 gap-2 sm:grid-cols-6 sm:gap-3">
          {holdings.map((h) => (
            <li key={h.key}>
              <Link href={holdingHref(h)} className="sleeve group relative block rounded-lg p-1.5">
                <ProductImage product={h.product} grade={h.identity.grade} slabKey={h.key} size="sm" frame={h.product?.kind !== "single"} className="aspect-[5/7] w-full rounded-md transition-transform duration-500 ease-[var(--ease-apple)] group-hover:-translate-y-1" />
                <span className="tabular absolute bottom-0 left-1/2 -translate-x-1/2 translate-y-1/2 -rotate-2 rounded-sm bg-[#f5f5f7] px-1.5 py-px font-mono text-[10px] font-bold text-[#0b0b0c] shadow">{money(h.value)}</span>
              </Link>
            </li>
          ))}
          <li>
            <button type="button" onClick={() => openAdd()} className="sleeve flex aspect-[5/7] w-full flex-col items-center justify-center gap-1 rounded-lg border border-dashed border-white/15 text-subtle transition-colors hover:text-foreground">
              <Plus className="size-5" />
              <span className="font-mono text-[10px] uppercase tracking-[0.06em]">Next pull</span>
            </button>
          </li>
        </ol>
      </div>
    </div>
  );
}

/* ------------------------------ G. Hand fan ------------------------------- */

/** The adds held like a hand of cards; hover or tap one to pull it up and read it. */
export function ActivityHand({ holdings }: { holdings: HoldingView[] }) {
  const [sel, setSel] = useState(0);
  const n = holdings.length;
  const h = holdings[Math.min(sel, n - 1)];
  if (!h) return null;
  const g = gainOf(h);
  return (
    <div className="tint tint-teal hype-surface min-w-0 overflow-hidden rounded-[var(--radius-card)] p-6 sm:p-7">
      <Heading />
      <div className="relative mx-auto h-[210px] max-w-[520px] sm:h-[250px]">
        {holdings.map((x, i) => {
          const t = n > 1 ? i / (n - 1) - 0.5 : 0;
          const on = i === sel;
          return (
            <button
              key={x.key}
              type="button"
              onMouseEnter={() => setSel(i)}
              onFocus={() => setSel(i)}
              onClick={() => setSel(i)}
              aria-label={x.product?.name ?? "Holding"}
              aria-pressed={on}
              className="absolute bottom-0 left-1/2 w-[110px] origin-bottom transition-transform duration-500 ease-[var(--ease-apple)] sm:w-[140px]"
              style={{ transform: `translateX(calc(-50% + ${t * 230}%)) translateY(${on ? -26 : Math.abs(t) * 30}px) rotate(${t * 34}deg)`, zIndex: on ? 10 : i }}
            >
              <ProductImage product={x.product} grade={x.identity.grade} slabKey={x.key} size="md" frame={x.product?.kind !== "single"} className="aspect-[5/7] w-full rounded-xl shadow-xl shadow-black/60" />
            </button>
          );
        })}
      </div>
      <Link key={h.key} href={holdingHref(h)} className="animate-rise mt-6 flex items-end justify-between gap-4 border-t border-white/[0.08] pt-4">
        <div className="min-w-0">
          <p className="font-mono text-[10px] uppercase tracking-[0.06em] text-subtle">{formatDate(h.lastAcquired)}</p>
          <p className="truncate font-display text-[22px] uppercase leading-tight tracking-[0.01em]">{h.product?.name}</p>
        </div>
        <div className="shrink-0 text-right">
          <p className="hype-num tabular text-[20px]">{money(h.value)}</p>
          <p className={cn("tabular text-[12px]", g === null ? "text-subtle" : g >= 0 ? "text-up" : "text-down")}>{g === null ? "—" : `${signedMoney(g)} since`}</p>
        </div>
      </Link>
    </div>
  );
}

/* --------------------------- H. Paid vs worth ----------------------------- */

/** Two faint bars per add, paid against worth now; only the numbers carry color. */
export function ActivityBars({ holdings }: { holdings: HoldingView[] }) {
  const max = Math.max(1, ...holdings.flatMap((h) => [h.costBasis, h.value ?? 0]));
  return (
    <div className="tint tint-blue hype-surface min-w-0 rounded-[var(--radius-card)] p-6 sm:p-7">
      <Heading />
      <div className="mb-4 flex gap-4 font-mono text-[10px] uppercase tracking-[0.06em] text-subtle">
        <span className="flex items-center gap-1.5"><span className="h-1.5 w-4 rounded-full bg-white/15" /> Paid</span>
        <span className="flex items-center gap-1.5"><span className="h-1.5 w-4 rounded-full bg-[var(--lime)]/30" /> Worth now</span>
      </div>
      <ol className="space-y-4">
        {holdings.map((h, i) => {
          const g = gainOf(h);
          const up = (g ?? 0) >= 0;
          return (
            <li key={h.key}>
              <Link href={holdingHref(h)} className="group grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-4 gap-y-1.5">
                <p className="truncate text-[14px] font-medium">{h.product?.name}</p>
                <p className={cn("hype-num tabular row-span-3 text-right text-[18px]", g === null ? "text-subtle" : up ? "text-up" : "text-down")}>{g === null ? "—" : signedMoney(g)}</p>
                <span className="block h-1.5 rounded-full bg-white/15 animate-grow-x origin-left" style={{ width: `${(h.costBasis / max) * 100}%`, animationDelay: `${i * 80}ms` }} />
                <span className={cn("block h-1.5 origin-left rounded-full animate-grow-x", up ? "bg-[var(--lime)]/30" : "bg-[var(--down)]/30")} style={{ width: `${((h.value ?? 0) / max) * 100}%`, animationDelay: `${i * 80 + 120}ms` }} />
              </Link>
            </li>
          );
        })}
      </ol>
    </div>
  );
}

/* ------------------------------ I. By period ------------------------------ */

/** Adds grouped into This week, This month and Earlier, each with what went in and what it's worth now. */
export function ActivityPeriods({ holdings }: { holdings: HoldingView[] }) {
  const { today } = useStore();
  const groups = useMemo(() => {
    const out: { name: string; items: HoldingView[] }[] = [
      { name: "This week", items: [] },
      { name: "This month", items: [] },
      { name: "Earlier", items: [] },
    ];
    for (const h of holdings) {
      const d = h.lastAcquired ? daysBetween(h.lastAcquired, today) : Infinity;
      out[d < 7 ? 0 : d < 31 ? 1 : 2].items.push(h);
    }
    return out.filter((g) => g.items.length);
  }, [holdings, today]);
  return (
    <div className="tint tint-orange hype-surface min-w-0 rounded-[var(--radius-card)] p-6 sm:p-7">
      <Heading />
      <div className="grid gap-4 md:grid-cols-[repeat(var(--n),minmax(0,1fr))]" style={{ "--n": groups.length } as React.CSSProperties}>
        {groups.map((grp) => {
          const paid = grp.items.reduce((s, h) => s + h.costBasis, 0);
          const worth = grp.items.reduce((s, h) => s + (h.value ?? 0), 0);
          return (
            <section key={grp.name} className="min-w-0 rounded-2xl bg-background/40 p-4 ring-1 ring-inset ring-white/[0.06]">
              <div className="flex items-baseline justify-between gap-2">
                <h3 className="font-display text-[18px] uppercase tracking-[0.01em]">{grp.name}</h3>
                <span className={cn("hype-num tabular text-[15px]", worth >= paid ? "text-up" : "text-down")}>{signedMoney(worth - paid)}</span>
              </div>
              <p className="tabular mt-0.5 font-mono text-[10px] uppercase tracking-[0.06em] text-subtle">
                {grp.items.length} add{grp.items.length === 1 ? "" : "s"} · {money(paid)} in
              </p>
              <ul className="mt-3 space-y-2">
                {grp.items.map((h) => (
                  <li key={h.key}>
                    <Link href={holdingHref(h)} className="flex items-center gap-2.5 hover:text-foreground">
                      <ProductImage product={h.product} size="xs" className="h-10 w-8 shrink-0 rounded-md" />
                      <span className="min-w-0 flex-1 truncate text-[13px] text-foreground/85">{h.product?.name}</span>
                      <span className="hype-num tabular text-[13px]">{money(h.value)}</span>
                    </Link>
                  </li>
                ))}
              </ul>
            </section>
          );
        })}
      </div>
    </div>
  );
}

/* --------------------------- J. Since you bought -------------------------- */

/** Each add's price from the day you bought it to today, with a dashed line at what you paid. */
export function ActivitySince({ holdings }: { holdings: HoldingView[] }) {
  const { data, today } = useStore();
  const series = useMemo(
    () =>
      holdings.map((h) => {
        if (h.priceOrigin === "manual") return [];
        const key = priceKey(h.identity.productId, h.identity.printing);
        const all = data.history[key] ?? [];
        const from = h.lastAcquired ?? addDays(today, -30);
        let pts = all.filter((p) => p.date >= from && p.date < today).map((p) => p.price);
        if (pts.length < 3) pts = all.filter((p) => p.date >= addDays(today, -30) && p.date < today).map((p) => p.price);
        // Slabs follow their card's raw trend, scaled to the slab's price.
        const raw = data.prices[key]?.market;
        if (h.identity.grade && h.price !== null && raw) pts = pts.map((p) => (p * h.price!) / raw);
        if (h.price !== null) pts.push(h.price);
        return pts;
      }),
    [holdings, data.history, data.prices, today],
  );
  return (
    <div className="tint tint-lime hype-surface min-w-0 rounded-[var(--radius-card)] p-6 sm:p-7">
      <Heading />
      <ol className="divide-y divide-white/[0.06]">
        {holdings.map((h, i) => {
          const g = gainOf(h);
          const up = (g ?? 0) >= 0;
          return (
            <li key={h.key}>
              <Link href={holdingHref(h)} className="grid grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-4 py-3 sm:grid-cols-[auto_minmax(0,1fr)_minmax(0,1.2fr)_auto]">
                <ProductImage product={h.product} size="xs" className="h-12 w-9 rounded-md" />
                <div className="min-w-0">
                  <p className="truncate text-[14px] font-medium">{h.product?.name}</p>
                  <p className="font-mono text-[10px] uppercase tracking-[0.06em] text-subtle">Since {formatDate(h.lastAcquired)}</p>
                </div>
                <div className="hidden sm:block">
                  {series[i].length > 2 ? <Sparkline values={series[i]} tone={up ? "up" : "down"} reference={h.avgCost} className="w-full" height={36} /> : <span className="text-[12px] text-subtle">No history yet</span>}
                </div>
                <div className="text-right">
                  <p className={cn("hype-num tabular text-[16px]", g === null ? "text-subtle" : up ? "text-up" : "text-down")}>{g === null ? "—" : signedMoney(g)}</p>
                  <p className="tabular text-[11px] text-muted">{money(h.value)}</p>
                </div>
              </Link>
            </li>
          );
        })}
      </ol>
    </div>
  );
}
