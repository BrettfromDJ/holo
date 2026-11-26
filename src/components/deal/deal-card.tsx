"use client";

import { AlertTriangle, ArrowDownRight, ArrowUpRight, ChevronDown, Info, Pencil, X } from "lucide-react";
import { useState } from "react";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { aheadTitle, dealNet, dealVerdict, showsEquity, type CardTotals, type DealKind } from "@/lib/deal";
import { money, signedMoney } from "@/lib/format";
import { cn } from "@/lib/utils";
import { KIND_COLOR, KIND_LABEL, TERMS, type DealTerm } from "./deal-types";

const PINK = "#FF2E9A";
const INK = "#0b0b0c";

/** A colour at some opacity, for inline gradients. */
export function alpha(hex: string, a: number) {
  return `color-mix(in srgb, ${hex} ${Math.round(a * 100)}%, transparent)`;
}

/** What a figure means: a small dialog with its name, one line and a round close (the app's TermSheet). */
export function TermDialog({ term, onClose }: { term: DealTerm | null; onClose: () => void }) {
  const t = term ? TERMS[term] : null;
  return (
    <Dialog open={term !== null} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="bg-[#161618] sm:max-w-[380px]">
        <div className="px-6 pb-7 pt-6 pr-12">
          <DialogTitle className="font-display text-[20px] tracking-[-0.02em]">{t?.title}</DialogTitle>
          <DialogDescription className="mt-2 text-[15px] leading-snug text-muted">{t?.text}</DialogDescription>
        </div>
      </DialogContent>
    </Dialog>
  );
}

/** A small caps label with an ⓘ; click it to read what it means. */
export function TermLabel({ label, term, className }: { label: string; term: DealTerm; className?: string }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button type="button" onClick={() => setOpen(true)} className={cn("inline-flex max-w-full items-center gap-1 whitespace-nowrap text-left font-mono text-[10px] uppercase tracking-[0.11em] text-white/65 hover:text-white", className)}>
        {label} <Info className="size-2.5 opacity-70" />
      </button>
      <TermDialog term={open ? term : null} onClose={() => setOpen(false)} />
    </>
  );
}

/**
 * The deal card (the app's BalanceCard): the kind tag, the verdict, who pays whom with the big
 * cash (click to type an agreed cash), the rate section passed in (deal page only), and the
 * per-kind figures behind Details (always shown on a summary). Glows in the deal kind's colour on
 * a dark middle; pink when the deal leaves you behind.
 */
export function DealCard({
  totals: t,
  tagKind,
  agreed = false,
  readOnly = false,
  past = false,
  onEditCash,
  rounded,
  extra,
  onEditMarket,
  marketAgreed = false,
}: {
  totals: CardTotals;
  /** The deal type picked (Trade stays Trade even while one side is still empty). */
  tagKind?: DealKind | null;
  agreed?: boolean;
  /** A summary (review, a closed deal): no pencil or chips, figures shown. */
  readOnly?: boolean;
  /** A closed deal: the past tense ("You made a profit", "They paid you"). */
  past?: boolean;
  onEditCash?: () => void;
  /** A rounded total: how far it moved, and Reset. */
  rounded?: { delta: number; onReset: () => void } | null;
  /** The rate section, under the amount. */
  extra?: React.ReactNode;
  /** Click Market value to type the market value you agreed on (the deal page only). */
  onEditMarket?: (() => void) | null;
  marketAgreed?: boolean;
}) {
  const [details, setDetails] = useState(false);
  const b = t.balance;
  const empty = t.kind === "empty";
  const down = (showsEquity(t) && t.equity < -0.005) || (t.ahead ?? 0) < -0.005;
  const kind = tagKind ?? t.kind;
  const colors = KIND_COLOR[kind];
  const fill = down ? PINK : colors.tint;
  const verdict = past ? (t.ahead !== null ? `${aheadTitle(t.ahead, true)} ${signedMoney(t.ahead)}` : dealVerdict(t)) : t.ahead !== null ? `${aheadTitle(t.ahead)} ${signedMoney(t.ahead)}` : dealVerdict(t);
  const score = t.ahead ?? dealNet(t) ?? 0;
  const cashLabel = empty ? "Add items to start" : Math.abs(b) < 0.005 ? "Settled · no cash" : b > 0 ? (past ? "They paid you" : "They pay you") : past ? "You paid them" : "You pay them";
  const tag = empty ? "New deal" : tagKind === "trade" ? KIND_LABEL.trade : KIND_LABEL[t.kind];
  return (
    <section
      aria-live="polite"
      className="relative overflow-hidden rounded-[24px] p-5 text-white"
      style={{
        background: [
          `radial-gradient(300px 300px at 10% -5%, ${alpha(fill, 0.75)}, transparent)`,
          `radial-gradient(230px 230px at 105% 20%, ${alpha(fill, 0.55)}, transparent)`,
          `radial-gradient(280px 280px at 55% 115%, ${alpha(fill, 0.7)}, transparent)`,
          `radial-gradient(190px 190px at 45% 50%, rgb(0 0 0 / 0.45), transparent)`,
          down ? "#3A0B22" : colors.base,
        ].join(", "),
        boxShadow: `inset 0 0 0 1px ${alpha(fill, 0.25)}, 0 0 44px -14px ${alpha(fill, 0.5)}`,
      }}
    >
      <div className="flex items-center justify-between gap-3">
        <span className="tag-skew" style={{ background: fill, color: down ? "#fff" : kind === "empty" ? INK : colors.onTint }}>
          {tag}
        </span>
        {t.belowCost > 0 && (
          <span className="flex items-center gap-1.5 text-[12px] font-semibold">
            <AlertTriangle className="size-3.5" /> {t.belowCost} below cost
          </span>
        )}
      </div>
      {verdict && (
        <p className="mt-4 inline-flex h-9 max-w-full items-center gap-2 rounded-full px-3.5 text-[15px] font-bold" style={{ background: alpha(INK, 0.85), color: score < -0.005 ? PINK : fill }}>
          {score >= 0 ? <ArrowUpRight className="size-3.5 shrink-0" /> : <ArrowDownRight className="size-3.5 shrink-0" />}
          <span className="truncate">{verdict}</span>
        </p>
      )}
      {details && t.uncosted > 0 && !readOnly && <p className="mt-2 text-[12px] font-medium text-white/70">Add what you paid for every item to see your total</p>}
      <div className="mt-4">
        <TermLabel label={cashLabel} term="cash" />
      </div>
      <div className="mt-1.5 flex items-center gap-2">
        {readOnly || empty || !onEditCash ? (
          <span className="tabular font-display text-[52px] leading-none tracking-[-0.04em] sm:text-[60px]">{money(Math.abs(b))}</span>
        ) : (
          <button type="button" onClick={onEditCash} aria-label={`Cash ${money(Math.abs(b))}. Type the cash you agreed on`} className="group -mx-1 inline-flex min-w-0 items-center gap-1.5 rounded-xl px-1 text-left hover:bg-white/[0.05]">
            <span className="tabular font-display text-[52px] leading-none tracking-[-0.04em] sm:text-[60px]">{money(Math.abs(b))}</span>
            <Pencil aria-hidden className="size-4 shrink-0 text-white/70 group-hover:text-white" />
          </button>
        )}
      </div>
      {rounded && Math.abs(rounded.delta) >= 0.005 && (
        <p className="tabular mt-2 text-[13px] font-medium text-white/75">
          Rounded {signedMoney(rounded.delta)} ·{" "}
          <button type="button" onClick={rounded.onReset} className="font-semibold text-white underline-offset-2 hover:underline">
            Reset
          </button>
        </p>
      )}
      {agreed && readOnly && <p className="mt-2 text-[12px] font-medium text-white/70">Agreed total</p>}
      {extra}
      {(details || readOnly) && !empty && (
        <div className="mt-[18px]">
          <DealFigures totals={t} past={past} onEditMarket={readOnly ? null : onEditMarket} marketAgreed={marketAgreed} />
        </div>
      )}
      {!empty && !readOnly && (
        <button type="button" onClick={() => setDetails((d) => !d)} aria-expanded={details} className="mt-3 inline-flex items-center gap-1 py-1.5 text-[13px] font-semibold text-white/75 hover:text-white">
          {details ? "Hide details" : "Details"} <ChevronDown className={cn("size-3 transition-transform", details && "rotate-180")} />
        </button>
      )}
    </section>
  );
}

/**
 * The card's figures, only those that apply (the app's DealFigures): a buy shows Market value ·
 * Buying rate · Profit; a sale You paid · Market value · Profit; a trade Coming in · Going out ·
 * Sale profit · Trade-in value. Profit reads "Loss" by itself when negative.
 */
export function DealFigures({ totals: t, past = false, onEditMarket, marketAgreed = false }: { totals: CardTotals; past?: boolean; onEditMarket?: (() => void) | null; marketAgreed?: boolean }) {
  const stat = (label: string, term: DealTerm, value: string) => (
    <div key={label} className="min-w-0">
      <TermLabel label={label} term={term} />
      <p className="tabular mt-1 truncate text-[17px] font-semibold">{value}</p>
    </div>
  );
  const market = (v: number | null) => {
    const label = marketAgreed ? "Agreed market" : "Market value";
    if (!onEditMarket) return stat(label, "market", v === null ? "—" : money(v));
    return (
      <div key="market" className="min-w-0">
        <TermLabel label={label} term="market" />
        <button type="button" onClick={onEditMarket} aria-label="Type the market value you agreed on" className="tabular mt-1 inline-flex max-w-full items-center gap-1 truncate text-[17px] font-semibold hover:opacity-90">
          {v === null ? "—" : money(v)} <Pencil className="size-3 shrink-0 text-white/70" />
        </button>
      </div>
    );
  };
  const gain = (v: number | null) => stat((v ?? 0) < -0.005 ? "Loss" : "Profit", "gain", v === null ? "—" : signedMoney(v));
  const cells =
    t.kind === "buy"
      ? [market(t.inMarket), stat(past ? "Paid at" : "Buying rate", "rate", t.inMarket && t.inMarket > 0 ? `${Math.round((t.inValue / t.inMarket) * 100)}%` : "—"), gain(t.ahead)]
      : t.kind === "sell"
        ? [stat("You paid", "paid", t.profit === null ? "—" : money(t.outValue - t.profit)), market(t.outMarket), gain(t.profit)]
        : [
            stat(past ? "Came in" : "Coming in", "comingIn", money(t.inValue)),
            stat(past ? "Went out" : "Going out", "goingOut", money(t.outValue)),
            stat("Sale profit", "profit", t.profit === null ? "—" : signedMoney(t.profit)),
            stat("Trade-in value", "value", showsEquity(t) ? signedMoney(t.equity) : "—"),
          ];
  return <div className={cn("grid gap-x-3 gap-y-3.5", t.kind === "buy" || t.kind === "sell" ? "grid-cols-3" : "grid-cols-2")}>{cells}</div>;
}

/** A round glass close button, for the top right of our own dialogs. */
export function RoundClose({ onClick, label = "Close" }: { onClick: () => void; label?: string }) {
  return (
    <button type="button" onClick={onClick} aria-label={label} className="glass-stat flex size-9 shrink-0 items-center justify-center rounded-full text-white hover:bg-white/[0.1]">
      <X className="size-4" />
    </button>
  );
}
