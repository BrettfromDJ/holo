"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import { ArrowRight, ChevronRight, Diff, ExternalLink, Hash, Pencil, Send, Square, Tag } from "lucide-react";
import Link from "next/link";
import { useMemo, useState } from "react";
import { SellCalculatorDialog } from "@/components/flows/sell-calculator";
import { ManualValueDialog, SaleDialog, TransactionActions, partitionHistory } from "@/components/flows/transaction-dialogs";
import { BumperDialog, CertDialog, SendToGraderDialog } from "@/components/grading/grading-items";
import { AnimatedNumber } from "@/components/motion/animated-number";
import { Sparkline } from "@/components/overview/sparkline";
import { DeltaPill } from "@/components/product/delta";
import { usePriceChartingGraded } from "@/components/product/graded-prices";
import { ProductImage } from "@/components/product/product-image";
import { bumperById } from "@/lib/bumpers";
import { addDays, daysBetween } from "@/lib/finance/dates";
import { acquisitionCost, saleProceeds } from "@/lib/finance/ledger";
import type { HoldingView } from "@/lib/finance/portfolio";
import { formatDate, money, signedMoney } from "@/lib/format";
import { certLookupUrl } from "@/lib/graded";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { useSlabBumpers, useSlabCerts } from "@/lib/store/grading";
import { holdingKey, priceKey, type Transaction } from "@/lib/types";
import { cn } from "@/lib/utils";
import { psaIfGraded } from "@/lib/worth";
import { holdingHref, holdingLabel } from "./holding-items";

/**
 * Your copy of a card, opened from Collection: what it's worth and what you made, its price line
 * since you bought it, what it would be worth graded (raw singles) or its cert and bumper
 * (slabs), sell or try a sale, its history, and a button to the full card page. A right-side
 * drawer on wide screens and a bottom sheet on phones. Port of the app's HoldingSheet.
 * Only the figures count up and the line draws in; the content itself sits still.
 */
export function HoldingSheet({ holding, onOpenChange }: { holding: HoldingView | null; onOpenChange: (open: boolean) => void }) {
  // Keeps the last copy on show while the sheet slides away.
  const [last, setLast] = useState(holding);
  if (holding && holding !== last) setLast(holding);
  const shown = holding ?? last;
  return (
    <DialogPrimitive.Root open={holding !== null} onOpenChange={onOpenChange}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="holding-sheet-overlay fixed inset-0 z-50 bg-black/45" />
        <DialogPrimitive.Content
          aria-describedby={undefined}
          className={cn(
            "holding-sheet fixed z-50 flex flex-col overflow-hidden outline-none",
            "bg-[color-mix(in_srgb,var(--background)_74%,transparent)] shadow-2xl shadow-black/50 ring-1 ring-inset ring-foreground/10 backdrop-blur-2xl backdrop-saturate-150",
            // Bottom sheet on phones, a drawer on the right on wider screens.
            "inset-x-0 bottom-0 max-h-[93dvh] rounded-t-[1.75rem] sm:inset-x-auto sm:bottom-3 sm:right-3 sm:top-3 sm:max-h-none sm:w-[440px] sm:rounded-[1.75rem]",
          )}
        >
          {shown && <SheetBody key={shown.key} opened={shown} close={() => onOpenChange(false)} />}
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

type Open = "sell" | "whatif" | "grade" | "cert" | "bumper" | "value" | null;

function SheetBody({ opened, close }: { opened: HoldingView; close: () => void }) {
  const { holdings } = usePortfolio({ ignoreFilter: true });
  // The copy now (after a sale or an edit), else as it was when the sheet opened.
  const live = holdings.find((h) => h.key === opened.key) ?? null;
  const h = live ?? opened;
  const product = h.product;
  const [open, setOpen] = useState<Open>(null);
  const dialog = (d: Exclude<Open, null>) => ({ open: open === d, onOpenChange: (o: boolean) => !o && setOpen(null) });
  const graded = Boolean(h.identity.grade);
  const rawSingle = !graded && product?.kind === "single";
  const tag = holdingLabel(h) ?? (product?.kind === "sealed" ? "Sealed" : h.identity.condition);

  return (
    <>
      <div className="sheet-scroll min-h-0 flex-1 overflow-y-auto overscroll-contain px-5 pb-6 pt-4 sm:px-6">
        {/* A grab handle on phones, where it's a bottom sheet. */}
        <div aria-hidden className="mx-auto mb-3 h-1 w-9 rounded-full bg-foreground/20 sm:hidden" />
        <div className="relative flex h-9 items-center justify-center">
          <DialogPrimitive.Title className="text-[17px] font-semibold">Your copy</DialogPrimitive.Title>
          <DialogPrimitive.Close className="absolute right-0 h-9 rounded-full bg-foreground/[0.09] px-3.5 text-[15px] font-semibold text-[var(--lime)] transition-colors hover:bg-foreground/[0.14]">Done</DialogPrimitive.Close>
        </div>

        {/* Header */}
        <div className="mt-5 flex items-center gap-3.5">
          <ProductImage product={product} grade={h.identity.grade} slabKey={h.key} size="sm" frame={!(product?.kind === "single" && product.imageUrl)} className="h-[86px] w-[62px] shrink-0 rounded-md" />
          <div className="min-w-0">
            <p className="line-clamp-2 text-[17px] font-semibold leading-snug">{product?.name ?? "Unknown product"}</p>
            <p className="mt-1.5 flex min-w-0 items-center gap-2">
              <span className={cn("shrink-0 rounded-full px-2 py-0.5 text-[11px] font-semibold ring-1 ring-inset", graded ? "text-[var(--lime)] ring-[color-mix(in_srgb,var(--lime)_40%,transparent)]" : "text-foreground ring-foreground/15")}>{tag}</span>
              {product?.setName && <span className="truncate text-[12px] text-muted">{product.setName}</span>}
            </p>
          </div>
        </div>

        {live ? (
          <>
            <Value h={live} />
            <dl className="mt-5 grid grid-cols-2 gap-2">
              <SheetStat label="Quantity" value={String(live.quantity)} />
              <SheetStat label="You paid" value={money(live.costBasis)} />
              <SheetStat label="Average cost" value={money(live.avgCost)} />
              <SheetStat label="Each now" value={(live.conditionEstimate && live.price !== null ? "≈ " : "") + money(live.price)} />
            </dl>
            {graded ? <SlabRows h={live} onCert={() => setOpen("cert")} onBumper={() => setOpen("bumper")} onValue={() => setOpen("value")} /> : rawSingle && <IfGraded h={live} onSend={() => setOpen("grade")} />}
            <div className="mt-5 grid grid-cols-2 gap-2">
              <button type="button" onClick={() => setOpen("sell")} className="sheet-panel flex h-11 items-center justify-center gap-2 rounded-full text-[14px] font-semibold transition-colors hover:bg-foreground/[0.11]">
                <Tag className="size-4" /> Sell
              </button>
              <button type="button" onClick={() => setOpen("whatif")} className="sheet-panel flex h-11 items-center justify-center gap-2 rounded-full text-[14px] font-semibold transition-colors hover:bg-foreground/[0.11]">
                <Diff className="size-4" /> What if I sell?
              </button>
            </div>
          </>
        ) : (
          <p className="mt-6 text-[14px] text-muted">You don&apos;t hold any of these right now.</p>
        )}

        <History h={h} />
      </div>

      <div className="border-t border-foreground/[0.06] px-5 pb-[max(1rem,env(safe-area-inset-bottom))] pt-3 sm:px-6 sm:pb-5">
        <Button3DLink href={holdingHref(h)} onClick={close} />
      </div>

      {live && (
        <>
          <SaleDialog holding={live} {...dialog("sell")} />
          <SellCalculatorDialog holding={live} {...dialog("whatif")} />
          {rawSingle && <SendToGraderDialog holding={live} {...dialog("grade")} />}
          {graded && <CertDialog holding={live} {...dialog("cert")} />}
          {graded && <BumperDialog h={live} {...dialog("bumper")} />}
          {graded && <ManualValueDialog holding={live} {...dialog("value")} />}
        </>
      )}
    </>
  );
}

/** "View card details →", the lime button pinned under the sheet. */
function Button3DLink({ href, onClick }: { href: string; onClick: () => void }) {
  return (
    <Link href={href} onClick={onClick} className="btn-3d btn-3d-lime flex h-12 w-full items-center justify-center gap-2 rounded-xl bg-lime text-[15px] font-semibold text-[#0b0b0c] transition-transform active:scale-[0.98]">
      View card details <ArrowRight className="size-4" />
    </Link>
  );
}

/** Small caps label, as in the app's MonoLabel. */
function MonoLabel({ children, className }: { children: React.ReactNode; className?: string }) {
  return <p className={cn("font-mono text-[10px] font-medium uppercase tracking-[0.06em] text-subtle", className)}>{children}</p>;
}

function SheetStat({ label, value, tint }: { label: string; value: string; tint?: boolean }) {
  return (
    <div className="sheet-panel min-w-0 rounded-[14px] px-3 py-2.5">
      <dt className="truncate font-mono text-[10px] font-medium uppercase tracking-[0.06em] text-subtle">{label}</dt>
      <dd className={cn("tabular mt-1 truncate text-[15px] font-semibold", tint && "text-[var(--lime)]")}>{value}</dd>
    </div>
  );
}

/** Your copy's value per unit since you first bought it (at least a week), slabs scaled from the raw trend. */
function useSinceSeries(h: HoldingView): number[] {
  const { data, today } = useStore();
  return useMemo(() => {
    if (h.priceOrigin === "manual") return [];
    const key = priceKey(h.identity.productId, h.identity.printing);
    const held = h.firstAcquired ? daysBetween(h.firstAcquired, today) : 90;
    const from = addDays(today, -Math.min(Math.max(held, 7), 3650));
    let pts = (data.history[key] ?? []).filter((p) => p.date >= from && p.date < today).map((p) => p.price);
    const raw = data.prices[key]?.market;
    if (h.identity.grade && h.price !== null && raw) pts = pts.map((p) => (p * h.price!) / raw);
    if (h.price !== null) pts.push(h.price);
    return pts;
  }, [h, data.history, data.prices, today]);
}

function Value({ h }: { h: HoldingView }) {
  const series = useSinceSeries(h);
  const gain = h.unrealized;
  const up = (gain ?? 0) >= 0;
  const since = h.firstAcquired ? new Date(`${h.firstAcquired}T00:00:00`).toLocaleDateString("en-US", { month: "short", year: "numeric" }) : null;
  return (
    <div className="mt-6">
      <MonoLabel>{h.quantity > 1 ? `Your ${h.quantity} are worth` : "Yours is worth"}</MonoLabel>
      <p className="tabular mt-2 font-display text-[44px] leading-[0.95]">
        {h.value !== null ? <AnimatedNumber value={h.value} format={(n) => (h.conditionEstimate ? "≈ " : "") + money(n)} /> : <span className="text-muted">No price</span>}
      </p>
      <p className="mt-2.5 flex flex-wrap items-center gap-2 text-[14px]">
        <DeltaPill ratio={h.unrealizedPct} className="text-[13px]" />
        {gain !== null && (
          <span className={cn("tabular font-semibold", up ? "text-up" : "text-down")}>
            <AnimatedNumber value={gain} format={signedMoney} />
          </span>
        )}
        <span className="text-[13px] text-muted">on what you paid</span>
      </p>
      {series.length > 1 && (
        <>
          {/* Colored by whether you're up overall, not by the line's own direction. */}
          <Sparkline values={series} tone={up ? "up" : "down"} className="mt-4 w-full" height={56} />
          <div className="mt-2 flex items-center justify-between gap-3">
            <MonoLabel>{since ? `Since you bought it · ${since}` : "Since you bought it"}</MonoLabel>
            <span className={cn("tabular text-[12px] font-semibold", up ? "text-up" : "text-down")}>{signedMoney(gain)}</span>
          </div>
        </>
      )}
    </div>
  );
}

/** A raw single: what it could be worth as a PSA 10 or 9, and a way to send it in. */
function IfGraded({ h, onSend }: { h: HoldingView; onSend: () => void }) {
  const { data } = useStore();
  const pc = usePriceChartingGraded(h.identity.productId);
  const nm = data.prices[priceKey(h.identity.productId, h.identity.printing)]?.market ?? h.price;
  if (nm === null) return null;
  const ten = psaIfGraded(h.identity.productId, nm, "10", pc.data);
  const nine = psaIfGraded(h.identity.productId, nm, "9", pc.data);
  return (
    <div className="mt-6">
      <MonoLabel>If graded</MonoLabel>
      <dl className={cn("mt-3 grid grid-cols-2 gap-2", !pc.ready && "animate-shimmer")}>
        <SheetStat label="PSA 10" value={pc.ready ? (ten.estimate ? "≈ " : "") + money(ten.price) : "—"} tint />
        <SheetStat label="PSA 9" value={pc.ready ? (nine.estimate ? "≈ " : "") + money(nine.price) : "—"} />
      </dl>
      <p className="mt-2.5 text-[12px] text-subtle">
        {!pc.ready ? "Looking up graded prices…" : ten.estimate ? "Estimates from the usual grade curve. The card page has every grade." : "From PriceCharting. The card page has every grade."}
      </p>
      <button type="button" onClick={onSend} className="sheet-panel mt-3 flex h-11 w-full items-center justify-center gap-2 rounded-full text-[14px] font-semibold transition-colors hover:bg-foreground/[0.11]">
        <Send className="size-4" /> Send for grading
      </button>
    </div>
  );
}

/** A slab: its cert number and bumper, and your own value. */
function SlabRows({ h, onCert, onBumper, onValue }: { h: HoldingView; onCert: () => void; onBumper: () => void; onValue: () => void }) {
  const { certs } = useSlabCerts();
  const { bumpers } = useSlabBumpers();
  const { data } = useStore();
  const cert = certs[h.key];
  const bumper = bumperById(bumpers[h.key]);
  const manual = data.manualValues[h.key];
  const grade = h.identity.grade!;
  return (
    <div className="sheet-panel mt-6 rounded-2xl px-3.5 py-1.5">
      <SlabRow icon={Hash} title="Cert number" value={cert ?? "Add"} onClick={onCert} />
      <div className="ml-11 h-px bg-foreground/[0.08]" />
      <SlabRow icon={Square} title="Bumper" value={bumper?.name ?? "Add"} onClick={onBumper} />
      <div className="ml-11 h-px bg-foreground/[0.08]" />
      <SlabRow icon={Pencil} title="Your value" value={manual ? money(manual.value) : "Set"} onClick={onValue} />
      {cert && (
        <a href={certLookupUrl(grade.company, cert)} target="_blank" rel="noreferrer" className="mb-2 mt-1 inline-flex items-center gap-1.5 text-[14px] font-medium text-foreground/90 hover:text-foreground">
          <ExternalLink className="size-4" /> Look up cert {cert}
        </a>
      )}
    </div>
  );
}

function SlabRow({ icon: Icon, title, value, onClick }: { icon: React.ElementType; title: string; value: string; onClick: () => void }) {
  return (
    <button type="button" onClick={onClick} className="flex w-full items-center gap-3 py-2.5 text-left">
      <span className="flex w-8 justify-center text-[var(--lime)]">
        <Icon className="size-4" strokeWidth={2.25} />
      </span>
      <span className="flex-1 text-[15px]">{title}</span>
      <span className="tabular truncate text-[14px] font-medium text-muted">{value}</span>
      <ChevronRight className="size-3.5 shrink-0 text-subtle" />
    </button>
  );
}

/** This copy's purchases and sales, newest first, each with Edit and Delete. */
function History({ h }: { h: HoldingView }) {
  const { data } = useStore();
  const rows = useMemo(() => {
    const { effective, visible } = partitionHistory(data.transactions.filter((t) => t.productId === h.identity.productId));
    const byNewest = (a: Transaction, b: Transaction) => (a.date === b.date ? (a.createdAt < b.createdAt ? 1 : -1) : a.date < b.date ? 1 : -1);
    return visible
      .map((t) => ({ t, shown: effective.get(t.id) ?? t }))
      .filter(({ shown }) => holdingKey(shown) === h.key)
      .sort((a, b) => byNewest(a.shown, b.shown));
  }, [data.transactions, h.identity.productId, h.key]);

  return (
    <div className="mt-6">
      <MonoLabel>History</MonoLabel>
      <ul className="sheet-panel mt-2 rounded-2xl px-3.5">
        {rows.map(({ t, shown }) => {
          const q = Math.abs(shown.quantity);
          const title = t.type === "sale" ? `Sold ${q}` : t.type === "adjustment" ? `${shown.quantity > 0 ? "Added" : "Removed"} ${q}` : `Bought ${q}`;
          const sub = [formatDate(shown.date), shown.unitPrice > 0 ? `${money(shown.unitPrice)} each` : null, shown.source].filter(Boolean).join(" · ");
          return (
            <li key={t.id} className="flex items-center gap-2 border-b border-foreground/[0.08] py-2.5 last:border-b-0">
              <div className="min-w-0 flex-1">
                <p className="text-[14px] font-medium">{title}</p>
                <p className="truncate text-[12px] text-muted">{sub}</p>
              </div>
              <span className="tabular text-[14px] font-semibold">{money(t.type === "sale" ? saleProceeds(shown) : acquisitionCost(shown))}</span>
              <TransactionActions tx={t} />
            </li>
          );
        })}
        {!rows.length && <li className="py-3 text-[14px] text-muted">No entries.</li>}
      </ul>
    </div>
  );
}
