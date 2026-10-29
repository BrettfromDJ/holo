"use client";

import { ArrowRight, Check } from "lucide-react";
import { ProductImage } from "@/components/product/product-image";
import { money, pct, signedMoney } from "@/lib/format";
import type { Product } from "@/lib/types";
import { cn } from "@/lib/utils";

/**
 * Prototype verdicts for the Trade checker, compared on /lab/trade.
 * Every one answers the same question first: do I come out ahead, and by how much?
 */

export interface VerdictItem {
  key: string;
  product: Product;
  value: number;
}
export interface VerdictProps {
  give: number;
  get: number;
  giveItems: VerdictItem[];
  getItems: VerdictItem[];
}

/** Within this share of the larger side, a trade counts as even. */
const FAIR = 0.05;

function outcome({ give, get }: { give: number; get: number }) {
  const net = get - give;
  const larger = Math.max(give, get);
  const gap = larger ? Math.abs(net) / larger : 0;
  const state: "win" | "lose" | "fair" = gap <= FAIR ? "fair" : net > 0 ? "win" : "lose";
  return { net, gap, state };
}

const toneText = { win: "text-up", lose: "text-down", fair: "text-foreground" };

function Headline({ give, get }: { give: number; get: number }) {
  const { net, state } = outcome({ give, get });
  return (
    <p className="text-balance text-[20px] font-semibold leading-tight tracking-[-0.02em]">
      {state === "fair" ? (
        "Fair trade"
      ) : state === "win" ? (
        <>
          You come out <span className="tabular text-up">{money(net)}</span> ahead
        </>
      ) : (
        <>
          You lose <span className="tabular text-down">{money(-net)}</span> on this
        </>
      )}
    </p>
  );
}

/* A. Net result: the answer as one big number, with the sum that makes it */
export function VerdictNet(p: VerdictProps) {
  const { net, state } = outcome(p);
  return (
    <div className="flex flex-col items-center text-center">
      <p className="font-mono text-[11px] uppercase tracking-[0.08em] text-subtle">{state === "fair" ? "Fair trade" : state === "win" ? "You come out ahead" : "You come out behind"}</p>
      <p className={cn("hype-num tabular mt-2 text-[64px] leading-none", toneText[state])}>{signedMoney(net)}</p>
      <div className="tabular mt-5 flex items-center gap-2 text-[13px]">
        <span className="rounded-full bg-surface-2 px-3 py-1.5">
          <span className="text-subtle">You get </span>
          <span className="font-semibold">{money(p.get)}</span>
        </span>
        <span className="text-subtle">−</span>
        <span className="rounded-full bg-surface-2 px-3 py-1.5">
          <span className="text-subtle">You give </span>
          <span className="font-semibold">{money(p.give)}</span>
        </span>
      </div>
    </div>
  );
}

/* B. Tug of war: one bar split between the two sides, a line at even, and the gap called out */
export function VerdictTug(p: VerdictProps) {
  const { state } = outcome(p);
  const total = p.give + p.get || 1;
  const giveShare = p.give / total;
  return (
    <div>
      <Headline {...p} />
      <div className="mt-5 flex justify-between font-mono text-[11px] uppercase tracking-[0.06em] text-subtle">
        <span>You give</span>
        <span>You get</span>
      </div>
      <div className="relative mt-2 flex h-12 overflow-hidden rounded-xl">
        <div className="flex items-center bg-[color-mix(in_srgb,var(--down)_22%,var(--surface-2))] px-3 transition-[width] duration-700 ease-[var(--ease-apple)]" style={{ width: `${giveShare * 100}%` }}>
          <span className="hype-num tabular truncate text-[18px]">{money(p.give)}</span>
        </div>
        <div className="flex flex-1 items-center justify-end bg-[color-mix(in_srgb,var(--up)_20%,var(--surface-2))] px-3">
          <span className="hype-num tabular truncate text-[18px]">{money(p.get)}</span>
        </div>
        {/* Even */}
        <span aria-hidden className="absolute inset-y-[-4px] left-1/2 w-0.5 -translate-x-1/2 bg-foreground/70" />
      </div>
      <p className="mt-2 text-center font-mono text-[10px] uppercase tracking-[0.08em] text-subtle">
        {state === "fair" ? "Close to even" : `Even is the line · ${state === "win" ? "more on your side" : "more on their side"}`}
      </p>
    </div>
  );
}

/* C. Fairness meter: a dial from "you lose" through "fair" to "you win" */
export function VerdictGauge(p: VerdictProps) {
  const { net, gap, state } = outcome(p);
  // Full swing at a 50% gap.
  const t = Math.max(-1, Math.min(1, (net >= 0 ? gap : -gap) / 0.5));
  const angle = t * 80;
  const arc = (from: number, to: number) => {
    const r = 80;
    const p0 = [100 + r * Math.sin((from * Math.PI) / 180), 100 - r * Math.cos((from * Math.PI) / 180)];
    const p1 = [100 + r * Math.sin((to * Math.PI) / 180), 100 - r * Math.cos((to * Math.PI) / 180)];
    return `M${p0[0]} ${p0[1]} A${r} ${r} 0 0 1 ${p1[0]} ${p1[1]}`;
  };
  const fairDeg = (FAIR / 0.5) * 80;
  return (
    <div className="flex flex-col items-center text-center">
      <svg viewBox="0 0 200 116" className="w-full max-w-[280px]" aria-hidden>
        <path d={arc(-80, -fairDeg)} fill="none" stroke="var(--down)" strokeOpacity={0.55} strokeWidth={14} strokeLinecap="round" />
        <path d={arc(-fairDeg, fairDeg)} fill="none" stroke="var(--foreground)" strokeOpacity={0.5} strokeWidth={14} />
        <path d={arc(fairDeg, 80)} fill="none" stroke="var(--up)" strokeOpacity={0.55} strokeWidth={14} strokeLinecap="round" />
        <g style={{ transform: `rotate(${angle}deg)`, transformOrigin: "100px 100px", transition: "transform 800ms cubic-bezier(0.32, 0.72, 0, 1)" }}>
          <line x1={100} y1={100} x2={100} y2={30} stroke="var(--foreground)" strokeWidth={3} strokeLinecap="round" />
        </g>
        <circle cx={100} cy={100} r={7} fill="var(--surface)" stroke="var(--foreground)" strokeWidth={3} />
        <text x={18} y={114} className="fill-[var(--subtle)] font-mono text-[8px] uppercase">You lose</text>
        <text x={100} y={12} textAnchor="middle" className="fill-[var(--subtle)] font-mono text-[8px] uppercase">Fair</text>
        <text x={182} y={114} textAnchor="end" className="fill-[var(--subtle)] font-mono text-[8px] uppercase">You win</text>
      </svg>
      <div className="mt-3">
        <Headline {...p} />
      </div>
      <p className="tabular mt-1.5 text-[12px] text-muted">
        {pct(gap, 0)} apart · {state === "fair" ? "within 5% is fair" : `give ${money(p.give)}, get ${money(p.get)}`}
      </p>
    </div>
  );
}

/* D. Two piles: each side as a column that grows with its value, cards stacked inside, the gap bracketed */
export function VerdictPiles(p: VerdictProps) {
  const { net, state } = outcome(p);
  const max = Math.max(p.give, p.get, 1);
  const pile = (label: string, value: number, items: VerdictItem[], tone: "down" | "up") => (
    <div className="flex flex-1 flex-col items-center">
      <div className="flex h-[180px] w-full items-end justify-center">
        <div
          className="relative flex w-full max-w-[120px] flex-col-reverse items-center gap-1 overflow-hidden rounded-t-xl px-2 pb-2 pt-2 transition-[height] duration-700 ease-[var(--ease-apple)]"
          style={{ height: `${Math.max(14, (value / max) * 100)}%`, background: `color-mix(in srgb, var(--${tone}) 16%, var(--surface-2))` }}
        >
          {items.slice(0, 3).map((it) => (
            <ProductImage key={it.key} product={it.product} size="xs" className="h-10 w-8 shrink-0 rounded-md" />
          ))}
        </div>
      </div>
      <p className="mt-2 font-mono text-[10px] uppercase tracking-[0.08em] text-subtle">{label}</p>
      <p className="hype-num tabular text-[20px]">{money(value)}</p>
    </div>
  );
  return (
    <div>
      <div className="flex items-end gap-4 border-b border-border">
        {pile("You give", p.give, p.giveItems, "down")}
        {pile("You get", p.get, p.getItems, "up")}
      </div>
      <div className="mt-4 text-center">
        <Headline {...p} />
        {state !== "fair" && <p className="tabular mt-1 text-[12px] text-muted">The taller pile is worth {money(Math.abs(net))} more</p>}
      </div>
    </div>
  );
}

/* E. Swap: what leaves your collection, an arrow, what comes in, and the result as a stamp */
export function VerdictSwap(p: VerdictProps) {
  const { net, state } = outcome(p);
  const fan = (items: VerdictItem[]) => (
    <div className="relative flex h-[120px] w-full items-center justify-center">
      {items.slice(0, 3).map((it, i, arr) => {
        const t = arr.length > 1 ? i / (arr.length - 1) - 0.5 : 0;
        return (
          <div key={it.key} className="absolute w-[64px]" style={{ transform: `translateX(${t * 70}px) rotate(${t * 18}deg)`, zIndex: i }}>
            <ProductImage product={it.product} size="sm" className="aspect-[5/7] w-full rounded-lg shadow-lg shadow-black/50" />
          </div>
        );
      })}
    </div>
  );
  return (
    <div>
      <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-2">
        <div className="text-center">
          {fan(p.giveItems)}
          <p className="mt-1 font-mono text-[10px] uppercase tracking-[0.08em] text-subtle">Leaves your collection</p>
          <p className="hype-num tabular text-[20px]">{money(p.give)}</p>
        </div>
        <ArrowRight className="size-6 text-subtle" />
        <div className="text-center">
          {fan(p.getItems)}
          <p className="mt-1 font-mono text-[10px] uppercase tracking-[0.08em] text-subtle">Comes in</p>
          <p className="hype-num tabular text-[20px]">{money(p.get)}</p>
        </div>
      </div>
      <div className="mt-5 flex justify-center">
        <span className={cn("tag-skew !px-4 !py-1.5 !text-[15px]", state === "win" ? "tag-lime" : state === "lose" ? "tag-pink" : "tag-white")}>
          {state === "fair" ? (
            <>
              <Check className="size-4" /> Fair trade
            </>
          ) : state === "win" ? (
            `You gain ${money(net)}`
          ) : (
            `You lose ${money(-net)}`
          )}
        </span>
      </div>
    </div>
  );
}

/* F. Ledger: both sides itemized like a statement, ending in a balance line */
export function VerdictLedger(p: VerdictProps) {
  const { net, state } = outcome(p);
  const rows = (items: VerdictItem[], sign: "+" | "−") =>
    items.map((it) => (
      <li key={it.key} className="flex items-center gap-3 py-1.5">
        <ProductImage product={it.product} size="xs" className="h-9 w-7 shrink-0 rounded-md" />
        <span className="min-w-0 flex-1 truncate text-[13px]">{it.product.name}</span>
        <span className={cn("tabular text-[13px] font-medium", sign === "+" ? "text-up" : "text-down")}>
          {sign}
          {money(it.value)}
        </span>
      </li>
    ));
  return (
    <div className="font-[450]">
      <p className="font-mono text-[10px] uppercase tracking-[0.08em] text-subtle">Coming in</p>
      <ul className="mt-1">{rows(p.getItems, "+")}</ul>
      <p className="mt-3 font-mono text-[10px] uppercase tracking-[0.08em] text-subtle">Going out</p>
      <ul className="mt-1">{rows(p.giveItems, "−")}</ul>
      <div className="mt-3 flex items-baseline justify-between border-t-2 border-double border-border-strong pt-3">
        <span className="font-mono text-[11px] uppercase tracking-[0.08em] text-subtle">{state === "fair" ? "Balance · fair" : "Balance"}</span>
        <span className={cn("hype-num tabular text-[28px] leading-none", toneText[state])}>{signedMoney(net)}</span>
      </div>
    </div>
  );
}
