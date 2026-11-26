"use client";

import { Check, Layers } from "lucide-react";
import { ProductImage } from "@/components/product/product-image";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { aheadTitle, showsEquity, type DealKind, type DealTotals } from "@/lib/deal";
import { money, signedMoney } from "@/lib/format";
import { cn } from "@/lib/utils";
import { DealCard } from "./deal-card";
import { KindButton } from "./deal-dialogs";
import type { DealItem } from "./deal-picker";
import { KIND_LABEL, KIND_NOUN, type DealRecord, type DealState } from "./deal-types";

/**
 * Before a deal closes (the app's DealCloseSheet): the deal card as a read-only summary, the
 * Buying / Selling rows with their cards, what happens to your collection, and Complete deal in
 * the deal kind's colour.
 */
export function ReviewDialog({ open, onOpenChange, path, totals, deal, effects, agreed, closing, demo, onClose }: { open: boolean; onOpenChange: (o: boolean) => void; path: DealKind; totals: DealTotals; deal: DealState; effects: { adds: number; sells: number; untracked: number }; agreed: boolean; closing: boolean; demo: boolean; onClose: () => void }) {
  const what = [effects.adds ? `Adds ${effects.adds} to your collection` : null, effects.sells ? `sells ${effects.sells} from it` : null, effects.untracked ? `${effects.untracked} not tracked` : null].filter(Boolean).join(" · ");
  const sideRow = (label: string, items: DealItem[], value: number) => {
    const count = items.reduce((s, i) => s + i.qty, 0);
    return (
      <div className="rounded-[18px] bg-surface p-4 ring-1 ring-inset ring-border">
        <div className="flex items-baseline gap-1.5">
          <span className="text-[16px] font-semibold">{label}</span>
          <span className="text-[13px] text-muted">
            {count} item{count === 1 ? "" : "s"}
          </span>
          <span className="tabular ml-auto text-[16px] font-semibold">{money(value)}</span>
        </div>
        <div className="mt-3 flex items-center -space-x-2.5">
          {items.slice(0, 8).map((i) => (
            <ProductImage key={i.key} product={i.product} size="xs" className="h-14 w-10 rounded-[3px] shadow-lg shadow-black/50" />
          ))}
          {items.length > 8 && <span className="pl-5 text-[12px] font-semibold text-muted">+{items.length - 8}</span>}
        </div>
      </div>
    );
  };
  return (
    <Dialog open={open} onOpenChange={(o) => !closing && onOpenChange(o)}>
      <DialogContent className="bg-[#161618] sm:top-[4vh] sm:max-h-[92dvh] sm:max-w-[480px]">
        <div className="min-h-0 flex-1 space-y-[22px] overflow-y-auto px-5 pb-4 pt-6">
          <div className="space-y-2">
            <span className="tag-skew tag-lime">{KIND_LABEL[totals.kind]}</span>
            <DialogTitle className="text-balance font-display text-[30px] leading-none tracking-[-0.03em]">Close this {KIND_NOUN[totals.kind].toLowerCase()}?</DialogTitle>
          </div>
          <DealCard totals={totals} tagKind={path} agreed={agreed} readOnly />
          {deal.in.length > 0 && sideRow("Buying", deal.in, totals.inValue)}
          {deal.out.length > 0 && sideRow("Selling", deal.out, totals.outValue)}
          {what && (
            <p className="flex items-center gap-2 text-[14px] font-semibold">
              <Layers className="size-4" /> {what.charAt(0).toUpperCase() + what.slice(1)}
            </p>
          )}
          <DialogDescription className="text-[13px] text-muted">{demo ? "This is the demo collection: closing updates it in this browser only." : "Sales and purchases are added to your collection, and the deal goes in your history."}</DialogDescription>
        </div>
        <div className="space-y-2 px-5 pb-5 pt-2">
          <KindButton kind={path} disabled={closing} onClick={onClose}>
            {closing ? "Recording…" : `Complete deal · ${money(Math.abs(totals.balance))}`}
          </KindButton>
          <button type="button" disabled={closing} onClick={() => onOpenChange(false)} className="btn-3d btn-3d-dark h-12 w-full rounded-full bg-surface-2 text-[16px] font-semibold disabled:opacity-45">
            Keep editing
          </button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

/** The deal, recorded: an electric-lime card (pink if it left you behind) with how it ended and what changed hands. */
export function RecordedDialog({ recorded, onDone }: { recorded: { record: DealRecord; totals: DealTotals; deal: DealState } | null; onDone: () => void }) {
  if (!recorded) return null;
  const { record, totals, deal } = recorded;
  const ahead = totals.ahead;
  // The headline figure decides the color: down turns the whole card pink (never pink on lime).
  const down = (showsEquity(totals) && totals.equity < -0.005) || (ahead !== null && ahead < -0.005);
  const headline = totals.profit !== null ? { label: "Sale profit", value: totals.profit } : totals.inValue > 0 ? { label: "Trade-in value", value: totals.equity } : null;
  const items = [...deal.out, ...deal.in].slice(0, 7);
  const b = totals.balance;
  const cash = Math.abs(b) < 0.005 ? "Even trade" : b > 0 ? `They paid ${money(b)}` : `You paid ${money(-b)}`;
  return (
    <Dialog open onOpenChange={(o) => !o && onDone()}>
      <DialogContent hideClose className={cn("overflow-hidden border-0 sm:max-w-[460px]", down ? "bg-[var(--plan-pink)] text-white" : "bg-[var(--lime)] text-[#0b0b0c]")} aria-describedby={undefined}>
        <div className="flex flex-col items-center px-6 pb-6 pt-10 text-center">
          <span className={cn("flex size-20 items-center justify-center rounded-full", down ? "bg-white text-[var(--plan-pink)]" : "bg-[#0b0b0c] text-[var(--lime)]")}>
            <Check className="size-9" strokeWidth={1.75} />
          </span>
          <p className="mt-5 font-mono text-[11px] uppercase tracking-[0.14em] opacity-60">In your collection</p>
          <DialogTitle className="mt-1 font-display text-[38px] leading-[0.92] tracking-[-0.03em]">{KIND_NOUN[record.kind]} recorded</DialogTitle>
          {items.length > 0 && (
            <div className="relative mt-6 h-28 w-full">
              {items.map((i, n) => {
                const off = n - (items.length - 1) / 2;
                return (
                  <span key={i.key} className="absolute left-1/2 top-0 origin-bottom" style={{ transform: `translateX(calc(-50% + ${off * 34}px)) rotate(${off * 9}deg)` }}>
                    <ProductImage product={i.product} size="sm" className="h-24 w-[68px] rounded-md shadow-xl shadow-black/30" />
                  </span>
                );
              })}
            </div>
          )}
          {ahead !== null ? (
            <>
              <p className="mt-4 font-display text-[22px] leading-none tracking-[-0.02em]">{aheadTitle(ahead, true)}</p>
              <p className="tabular mt-1 font-display text-[64px] leading-none tracking-[-0.04em]">{signedMoney(ahead)}</p>
            </>
          ) : (
            headline && (
              <>
                <p className="mt-4 font-mono text-[11px] uppercase tracking-[0.14em] opacity-60">{headline.label}</p>
                <p className="tabular font-display text-[64px] leading-none tracking-[-0.04em]">{signedMoney(headline.value)}</p>
                {totals.uncosted > 0 && <p className="mt-2 text-[12px] font-medium opacity-70">Total unknown: not every item had a cost</p>}
              </>
            )
          )}
          <div className="mt-5 flex flex-wrap justify-center gap-1.5">
            {[cash, `${record.items} item${record.items === 1 ? "" : "s"}`, record.photos?.length ? `${record.photos.length} photo${record.photos.length === 1 ? "" : "s"}` : null]
              .filter(Boolean)
              .map((t) => (
                <span key={t} className={cn("tabular rounded-full px-3 py-1.5 text-[13px] font-semibold", down ? "bg-white text-[var(--plan-pink)]" : "bg-[#0b0b0c] text-[var(--lime)]")}>
                  {t}
                </span>
              ))}
          </div>
          <button type="button" onClick={onDone} className={cn("mt-7 h-12 w-full rounded-full text-[16px] font-semibold", down ? "bg-white text-[var(--plan-pink)]" : "bg-[#0b0b0c] text-[var(--lime)]")}>
            Done
          </button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
