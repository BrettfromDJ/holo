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

/* ---------------------------- Round two ---------------------------------- */

/** A word and a 1–10 grade for how good the trade is for you, from the ratio of what you get to what you give. */
function rating({ give, get }: { give: number; get: number }) {
  const r = give ? get / give : get ? 2 : 1;
  if (r >= 1.15) return { grade: 10, word: "Steal", tone: "win" as const };
  if (r > 1 + FAIR) return { grade: 9, word: "Great", tone: "win" as const };
  if (r >= 1 - FAIR) return { grade: 8, word: "Fair", tone: "fair" as const };
  if (r >= 0.85) return { grade: 6, word: "Slight loss", tone: "lose" as const };
  if (r >= 0.7) return { grade: 4, word: "Bad deal", tone: "lose" as const };
  return { grade: 2, word: "Rip-off", tone: "lose" as const };
}

/* G. Trade grade: the trade graded like a slab, 1 to 10, on a red-trim label */
export function VerdictGrade(p: VerdictProps) {
  const { net } = outcome(p);
  const r = rating(p);
  return (
    <div className="flex flex-col items-center">
      <div className="w-full max-w-[260px] rounded-[18px] bg-gradient-to-b from-white/25 to-white/5 p-[7px] shadow-[0_20px_40px_-18px_rgb(0_0_0/0.8)] ring-1 ring-white/20">
        <div className="rounded-[12px] border-[3px] border-[#d0202a] bg-[#f4f4f1] px-3 py-2.5 text-[#0b0b0c]">
          <div className="flex items-start justify-between gap-2 font-sans text-[10px] font-bold uppercase leading-tight">
            <div>
              <p>Holo trade check</p>
              <p className="font-medium opacity-70">
                {p.giveItems.length} out · {p.getItems.length} in
              </p>
            </div>
            <div className="text-right">
              <p className="text-[11px]">{r.word}</p>
              <p className="font-display text-[34px] leading-none">{r.grade}</p>
            </div>
          </div>
          <div className="mt-1.5 flex items-center justify-between border-t border-black/15 pt-1.5">
            <span aria-hidden className="h-3 w-24 bg-[repeating-linear-gradient(90deg,#0b0b0c_0_2px,transparent_2px_4px,#0b0b0c_4px_5px,transparent_5px_7px)]" />
            <span className={cn("tabular text-[12px] font-bold", r.tone === "win" ? "text-[#2c7a00]" : r.tone === "lose" ? "text-[#c2124d]" : "")}>{signedMoney(net)}</span>
          </div>
        </div>
        <div className="mt-[7px] flex h-24 items-center justify-center gap-2 rounded-[12px] bg-black/40">
          {[...p.getItems, ...p.giveItems].slice(0, 4).map((it) => (
            <ProductImage key={it.key} product={it.product} size="xs" className="h-16 w-11 rounded-md" />
          ))}
        </div>
      </div>
      <p className="mt-4 text-center text-[13px] text-muted">
        Graded on what you get for what you give · <span className="text-foreground">10 is a steal</span>
      </p>
    </div>
  );
}

/* H. Versus: you against them, split on a slant, the winning side lit and the VS badge pushed toward the loser */
export function VerdictVersus(p: VerdictProps) {
  const { net, state } = outcome(p);
  const total = p.give + p.get || 1;
  // The split sits where the values put it, clamped so both sides stay readable.
  const split = Math.max(40, Math.min(60, (p.give / total) * 100));
  return (
    <div>
      <div className="relative h-[150px] overflow-hidden rounded-2xl">
        <div className="absolute inset-0 bg-[linear-gradient(135deg,color-mix(in_srgb,var(--down)_70%,#000),color-mix(in_srgb,var(--down)_25%,#000))]" style={{ clipPath: `polygon(0 0, calc(${split}% + 18px) 0, calc(${split}% - 18px) 100%, 0 100%)`, transition: "clip-path 800ms cubic-bezier(0.32,0.72,0,1)", opacity: state === "lose" ? 1 : 0.55 }} />
        <div className="absolute inset-0 bg-[linear-gradient(225deg,color-mix(in_srgb,var(--up)_75%,#000),color-mix(in_srgb,var(--up)_22%,#000))]" style={{ clipPath: `polygon(calc(${split}% + 18px) 0, 100% 0, 100% 100%, calc(${split}% - 18px) 100%)`, transition: "clip-path 800ms cubic-bezier(0.32,0.72,0,1)", opacity: state === "win" ? 1 : 0.55 }} />
        <div className="absolute left-0 top-0 flex flex-col pl-4 pt-4">
          <p className="font-mono text-[10px] uppercase tracking-[0.08em] text-white/70">You give</p>
          <p className="hype-num tabular text-[26px] leading-none text-white">{money(p.give)}</p>
        </div>
        <div className="absolute bottom-0 right-0 flex flex-col items-end pb-4 pr-4">
          <p className="font-mono text-[10px] uppercase tracking-[0.08em] text-black/60">You get</p>
          <p className="hype-num tabular text-[26px] leading-none text-[#0b0b0c]">{money(p.get)}</p>
        </div>
        <span className="absolute top-1/2 grid size-11 -translate-x-1/2 -translate-y-1/2 place-items-center rounded-full bg-[#0b0b0c] font-display text-[16px] text-white ring-2 ring-white/80" style={{ left: `${split}%`, transition: "left 800ms cubic-bezier(0.32,0.72,0,1)" }}>
          VS
        </span>
      </div>
      <p className="mt-4 text-center font-display text-[30px] uppercase leading-none tracking-[0.01em]">
        {state === "fair" ? "Dead even" : state === "win" ? <span className="text-up">You win {money(net)}</span> : <span className="text-down">They win {money(-net)}</span>}
      </p>
    </div>
  );
}

/* I. Steal-o-meter: a spectrum from rip-off to steal, with the result riding on it as a chip */
export function VerdictMeter(p: VerdictProps) {
  const { net } = outcome(p);
  const r = rating(p);
  const ratio = p.give ? p.get / p.give : 1;
  // 0.5x maps to the left end, 1.5x to the right.
  const pos = Math.max(4, Math.min(96, (ratio - 0.5) * 100));
  return (
    <div>
      <p className="text-center font-display text-[40px] uppercase leading-none tracking-[0.01em]">
        <span className={toneText[r.tone]}>{r.word}</span>
      </p>
      <div className="relative mt-10">
        <div className="h-3 rounded-full bg-[linear-gradient(90deg,var(--down),color-mix(in_srgb,var(--down)_30%,#fff)_42%,#fff_50%,color-mix(in_srgb,var(--up)_40%,#fff)_58%,var(--up))]" />
        <div className="absolute -top-9 -translate-x-1/2 transition-[left] duration-700 ease-[var(--ease-apple)]" style={{ left: `${pos}%` }}>
          <span className="tabular whitespace-nowrap rounded-full bg-foreground px-2.5 py-1 text-[12px] font-bold text-background shadow-lg">{signedMoney(net)}</span>
          <span className="mx-auto block h-0 w-0 border-x-[6px] border-t-[7px] border-x-transparent border-t-foreground" />
        </div>
        <span aria-hidden className="absolute -top-1 left-1/2 h-5 w-0.5 -translate-x-1/2 bg-background" />
      </div>
      <div className="mt-2 flex justify-between font-mono text-[10px] uppercase tracking-[0.08em] text-subtle">
        <span>Rip-off</span>
        <span>Fair</span>
        <span>Steal</span>
      </div>
      <p className="tabular mt-4 text-center text-[12px] text-muted">
        You give {money(p.give)} · you get {money(p.get)}
      </p>
    </div>
  );
}

/* J. Pull: the verdict revealed as a foil card, like opening a pack */
export function VerdictPull(p: VerdictProps) {
  const { net } = outcome(p);
  const r = rating(p);
  const foil = r.tone === "win" ? "var(--up)" : r.tone === "lose" ? "var(--down)" : "#f5f5f7";
  return (
    <div className="flex flex-col items-center">
      <div key={r.word} className="verdict-pull relative aspect-[63/88] w-[170px] overflow-hidden rounded-[12px] p-[6px]" style={{ "--foil": foil } as React.CSSProperties}>
        <div className="relative flex h-full flex-col rounded-[8px] bg-[#0b0b0c] p-3">
          <div className="flex items-center justify-between font-mono text-[9px] uppercase tracking-[0.08em] text-white/60">
            <span>Trade</span>
            <span>{r.grade}/10</span>
          </div>
          <div className="mt-2 flex flex-1 items-center justify-center rounded-md bg-[radial-gradient(circle_at_50%_40%,color-mix(in_srgb,var(--foil)_40%,transparent),transparent_70%)]">
            <span className="text-center font-display text-[30px] uppercase leading-[0.9] text-white">{r.word}</span>
          </div>
          <p className="hype-num tabular mt-2 text-center text-[22px] leading-none" style={{ color: foil }}>
            {signedMoney(net)}
          </p>
          <p className="mt-1 text-center text-[9px] text-white/50">
            {money(p.get)} in · {money(p.give)} out
          </p>
        </div>
      </div>
      <p className="mt-4 text-[13px] text-muted">Flips in each time the trade changes</p>
    </div>
  );
}

/* K. Head to head: the two sides as tinted plan cards, with the gap as a chip between them */
export function VerdictPlans(p: VerdictProps) {
  const { net, state } = outcome(p);
  const side = (label: string, value: number, items: VerdictItem[], color: "pink" | "lime", winner: boolean) => (
    <div className={cn("plan relative flex min-w-0 flex-1 flex-col rounded-2xl p-4", `plan-${color}`, !winner && state !== "fair" && "opacity-60")}>
      <span className={cn("tag-skew self-start", color === "lime" ? "tag-lime" : "tag-pink")}>{label}</span>
      <p className="hype-num tabular mt-3 text-[26px] leading-none">{money(value)}</p>
      <div className="mt-3 flex -space-x-3">
        {items.slice(0, 4).map((it) => (
          <ProductImage key={it.key} product={it.product} size="xs" className="h-12 w-9 rounded-md ring-2 ring-[var(--surface)]" />
        ))}
      </div>
      <p className="mt-2 text-[11px] text-white/60">
        {items.length} item{items.length === 1 ? "" : "s"}
      </p>
    </div>
  );
  return (
    <div className="relative flex gap-3 pb-5">
      {side("You give", p.give, p.giveItems, "pink", state === "lose")}
      {side("You get", p.get, p.getItems, "lime", state === "win")}
      <span className={cn("hype-num tabular absolute bottom-0 left-1/2 -translate-x-1/2 rounded-full px-3 py-1.5 text-[15px] shadow-xl ring-4 ring-[var(--surface)]", state === "win" ? "bg-[var(--lime)] text-[#0b0b0c]" : state === "lose" ? "bg-[var(--down)] text-white" : "bg-white text-[#0b0b0c]")}>
        {state === "fair" ? "=" : signedMoney(net)}
      </span>
    </div>
  );
}

/* L. Make it fair: the gap, then the quickest ways to close it */
export function VerdictFix(p: VerdictProps) {
  const { net, state } = outcome(p);
  // The one item whose removal from the bigger side gets closest to even.
  const bigger = net < 0 ? p.giveItems : p.getItems;
  const best = [...bigger].sort((a, b) => Math.abs(Math.abs(net) - a.value) - Math.abs(Math.abs(net) - b.value))[0];
  const after = best ? (net < 0 ? net + best.value : net - best.value) : null;
  if (state === "fair") {
    return (
      <div className="text-center">
        <Check className="mx-auto size-8 text-up" />
        <p className="mt-2 font-display text-[28px] uppercase leading-none">It&apos;s fair</p>
        <p className="tabular mt-2 text-[13px] text-muted">Within {signedMoney(net)} of even. Shake on it.</p>
      </div>
    );
  }
  return (
    <div>
      <p className="font-mono text-[10px] uppercase tracking-[0.08em] text-subtle">{state === "lose" ? "You're short" : "You're ahead by"}</p>
      <p className={cn("hype-num tabular text-[44px] leading-none", toneText[state])}>{money(Math.abs(net))}</p>
      <p className="mt-4 font-mono text-[10px] uppercase tracking-[0.08em] text-subtle">{state === "lose" ? "To make it fair" : "To be generous"}</p>
      <ul className="mt-2 space-y-2">
        <li className="flex items-center gap-3 rounded-xl bg-surface-2 px-3 py-2.5">
          <span className="grid size-9 shrink-0 place-items-center rounded-lg bg-background font-display text-[15px]">$</span>
          <span className="min-w-0 flex-1 text-[13px]">
            {state === "lose" ? "Ask for" : "Add"} <span className="tabular font-semibold">{money(Math.abs(net))}</span> cash
          </span>
        </li>
        {best && after !== null && (
          <li className="flex items-center gap-3 rounded-xl bg-surface-2 px-3 py-2.5">
            <ProductImage product={best.product} size="xs" className="h-9 w-7 shrink-0 rounded-md" />
            <span className="min-w-0 flex-1 text-[13px]">
              {state === "lose" ? "Keep" : "Give back"} <span className="font-semibold">{best.product.name}</span>
            </span>
            <span className={cn("tabular shrink-0 text-[12px] font-medium", Math.abs(after) <= Math.max(p.give, p.get) * FAIR ? "text-up" : "text-muted")}>{signedMoney(after)}</span>
          </li>
        )}
      </ul>
    </div>
  );
}
