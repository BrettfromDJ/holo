"use client";

import { Clock, ExternalLink, Minus, Plus, X } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import { Field, parseMoney } from "@/components/flows/fields";
import { FormShell } from "@/components/flows/transaction-dialogs";
import { Hint } from "@/components/ui/tooltip";
import { ProductImage } from "@/components/product/product-image";
import { Delta } from "@/components/product/delta";
import { Button } from "@/components/ui/button";
import { Dialog, DialogClose, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { daysBetween } from "@/lib/finance/dates";
import type { HoldingView } from "@/lib/finance/portfolio";
import { formatDate, money, moneyWhole } from "@/lib/format";
import { cachedEbay } from "@/lib/ebay-client";
import { certLookupUrl, gradeDescriptor, gradedSampleFor, gradeLabel, GRADERS, isStaleValue, liquidityLabel, liquidityNote, liquidityOf, sampleSalesPerYear } from "@/lib/graded";
import { useStore } from "@/lib/store/collection-store";
import { useGradingCosts, useGradingSubmissions, useSlabBumpers, useSlabCerts, type GradingSubmission } from "@/lib/store/grading";
import { BUMPERS, bumperById, GLITTER_SPECKS } from "@/lib/bumpers";
import { holdingKey, priceKey, type Grade } from "@/lib/types";
import { cn } from "@/lib/utils";

/** A small neutral chip: "PSA 10". */
export function GradeChip({ grade, className }: { grade: Grade; className?: string }) {
  return (
    <span className={cn("inline-flex items-center gap-1 rounded-[5px] bg-surface-2 px-1.5 py-0.5 font-mono text-[11px] font-medium leading-none ring-1 ring-inset ring-border", className)}>
      <span className="text-muted">{grade.company}</span>
      <span className="text-foreground">{grade.grade}</span>
    </span>
  );
}

function multipleLabel(m: number) {
  return `${m >= 10 ? m.toFixed(0) : m.toFixed(1)}×`;
}

/** The raw (ungraded) market price for a holding's card. */
export function useRawPrice(productId: string, printing: string | null): number | null {
  const { data } = useStore();
  return data.prices[priceKey(productId, printing)]?.market ?? null;
}

/** Three rising bars: one for hard to sell, three for easy. */
export function LiquidityMeter({ perYear, className }: { perYear: number; className?: string }) {
  const level = liquidityOf(perYear);
  const filled = level === "often" ? 3 : level === "regular" ? 2 : 1;
  return (
    <span className={cn("inline-flex items-end gap-[3px]", className)} role="img" aria-label={liquidityLabel(perYear)}>
      {[0, 1, 2].map((i) => (
        <span key={i} className={cn("w-[4px] rounded-full", i < filled ? "bg-foreground/80" : "bg-foreground/15")} style={{ height: `${7 + i * 4}px` }} />
      ))}
    </span>
  );
}

/** How easy a grade is to sell, as a meter with the label on hover. */
export function SalesCell({ perYear, className }: { perYear: number; className?: string }) {
  return (
    <Hint content={liquidityNote(perYear)}>
      <span className={cn("flex justify-end", className)}>
        <LiquidityMeter perYear={perYear} />
      </span>
    </Hint>
  );
}

/** A graded holding on its product page: the slab, its value, and tiles for premium, sales and cert. */
/** `showBumper` adds the bumper control here; off when it sits under the page's slab photo instead. */
export function SlabCard({ h, actions, onRevalue, onCert, showBumper = true }: { h: HoldingView; actions: React.ReactNode; onRevalue: () => void; onCert: () => void; showBumper?: boolean }) {
  const { today } = useStore();
  const { certs } = useSlabCerts();
  const raw = useRawPrice(h.identity.productId, h.identity.printing);
  const grade = h.identity.grade;
  if (!grade) return null;
  const cert = certs[h.key];
  const manual = h.priceOrigin === "manual";
  const stale = manual && isStaleValue(h.priceUpdatedAt, today);
  const sales = raw !== null ? salesPerYear(h.identity.productId, h.identity.printing, grade, raw) : null;

  return (
    <div className="flex gap-4 sm:gap-5">
      <ProductImage product={h.product} grade={grade} slabKey={h.key} size="md" className="h-[124px] w-[78px] shrink-0 sm:h-[176px] sm:w-[110px]" />
      <div className="min-w-0 flex-1">
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0">
            <p className="flex items-center gap-2">
              <span className="font-mono text-[11px] font-medium uppercase tracking-[0.06em] text-subtle">
                {h.quantity > 1 ? `${h.quantity} × ` : ""}
                {gradeLabel(grade)} · {gradeDescriptor(grade)}
              </span>
            </p>
            <p className="tabular mt-1 text-[26px] font-semibold leading-none tracking-[-0.02em]">{money(h.value)}</p>
            <p className="tabular mt-1.5 text-[12px] text-muted">
              <Delta value={h.unrealized} ratio={h.unrealizedPct} className="text-[12px]" /> <span className="text-subtle">on {money(h.costBasis)} cost</span>
            </p>
          </div>
          <div className="flex shrink-0 items-center gap-1">{actions}</div>
        </div>

        <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-3">
          <Tile label="Premium">
            {raw !== null && h.price !== null ? (
              <>
                <span className="font-mono text-[17px] font-semibold">{multipleLabel(h.price / raw)}</span>
                <span className="mt-0.5 block text-[11px] text-subtle">over raw {money(raw)}</span>
              </>
            ) : (
              <span className="text-muted">—</span>
            )}
          </Tile>
          <Tile label="Sells">
            {sales !== null ? (
              <Hint content={liquidityNote(sales)}>
                <span className="flex items-center gap-2.5">
                  <span className="text-[15px] font-semibold">{liquidityLabel(sales)}</span>
                  <LiquidityMeter perYear={sales} />
                </span>
              </Hint>
            ) : (
              <span className="text-muted">—</span>
            )}
          </Tile>
          <Tile label="Cert" className="col-span-2 sm:col-span-1">
            {cert ? (
              <>
                <span className="block truncate font-mono text-[15px] font-semibold">{cert}</span>
                <a href={certLookupUrl(grade.company, cert)} target="_blank" rel="noreferrer" className="mt-0.5 inline-flex items-center gap-0.5 text-[11px] font-medium text-muted hover:text-foreground">
                  Verify on {grade.company} <ExternalLink className="size-3" />
                </a>
              </>
            ) : (
              <button type="button" onClick={onCert} className="flex items-center gap-1 text-[13px] font-medium text-muted hover:text-foreground">
                <Plus className="size-3.5" /> Add cert number
              </button>
            )}
          </Tile>
        </div>

        <div className="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1.5 text-[12px] text-subtle">
          {showBumper && <BumperButton h={h} />}
          <span>{manual ? "Your value" : slabSourceLabel(h)}</span>
          <span>
            {h.lots.length} lot{h.lots.length === 1 ? "" : "s"} · avg {money(h.avgCost)}
          </span>
          {stale && (
            <button type="button" onClick={onRevalue} className="inline-flex items-center gap-1.5 whitespace-nowrap rounded-full bg-surface-2 px-2.5 py-1 font-medium text-foreground/85 ring-1 ring-inset ring-border hover:bg-surface-3">
              <Clock className="size-3" /> Value {daysBetween(h.priceUpdatedAt!, today)}d old · Update
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

/** Opens the bumper picker; shows the current bumper as a swatch. */
export function BumperButton({ h, className }: { h: HoldingView; className?: string }) {
  const { bumpers } = useSlabBumpers();
  const [open, setOpen] = useState(false);
  const current = bumperById(bumpers[h.key]);
  return (
    <>
      <button type="button" onClick={() => setOpen(true)} className={cn("inline-flex items-center gap-1.5 whitespace-nowrap rounded-full bg-surface-2 py-1 pl-1 pr-2.5 font-medium text-foreground/85 ring-1 ring-inset ring-border hover:bg-surface-3", className)}>
        <span className="size-4 rounded-full ring-1 ring-inset ring-white/20" style={{ background: current?.background ?? "transparent" }}>
          {!current && <Plus className="m-0.5 size-3 text-muted" />}
        </span>
        {current ? current.name : "Add bumper"}
      </button>
      <BumperDialog h={h} open={open} onOpenChange={setOpen} />
    </>
  );
}

/** Pick a bumper guard for a slab, with a live preview. */
export function BumperDialog({ h, open, onOpenChange }: { h: HoldingView; open: boolean; onOpenChange: (o: boolean) => void }) {
  const { bumpers, setBumper } = useSlabBumpers();
  const [pick, setPick] = useState<string | null>(null);
  // Start from the saved bumper each time the picker opens (not on every render).
  useEffect(() => {
    if (open) setPick(bumpers[h.key] ?? null);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only when opened
  }, [open, h.key]);
  const preview = bumperById(pick);
  const group = (kind: "glitter" | "solid", title: string) => (
    <div>
      <p className="mb-2 font-mono text-[10px] font-medium uppercase tracking-[0.06em] text-subtle">{title}</p>
      <div className="grid grid-cols-6 gap-2">
        {BUMPERS.filter((b) => b.kind === kind).map((b) => (
          <Hint key={b.id} content={b.name}>
            <button
              type="button"
              aria-label={b.name}
              aria-pressed={pick === b.id}
              onClick={() => setPick(b.id)}
              className={cn("aspect-square rounded-xl ring-1 ring-inset ring-white/15 transition-transform hover:scale-105", pick === b.id && "ring-2 ring-foreground ring-offset-2 ring-offset-[var(--surface)]")}
              style={{ background: b.kind === "glitter" ? `${GLITTER_SPECKS} 0 0 / 34px 34px, ${b.background}` : b.background }}
            />
          </Hint>
        ))}
      </div>
    </div>
  );
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[520px]">
        <FormShell
          title="Bumper"
          description="Snap a bumper guard around this slab. It shows everywhere the slab appears."
          onSubmit={(e) => {
            e.preventDefault();
            setBumper(h.key, pick);
            toast.success(pick ? `${bumperById(pick)?.name} bumper on` : "Bumper removed");
            onOpenChange(false);
          }}
          footer={
            <Button type="submit" variant="primary" size="lg" className="w-full">
              {pick ? "Save bumper" : "No bumper"}
            </Button>
          }
        >
          <div className="flex justify-center rounded-2xl bg-surface-2/60 py-5">
            <ProductImage product={h.product} grade={h.identity.grade} slabKey={h.key} bumper={preview ?? null} size="md" className="h-[220px] w-[140px]" />
          </div>
          {group("glitter", "Glitter")}
          {group("solid", "Solid")}
          <button type="button" onClick={() => setPick(null)} className={cn("text-[13px] font-medium", pick ? "text-muted hover:text-foreground" : "text-foreground")}>
            {pick ? "Remove bumper" : "No bumper selected"}
          </button>
        </FormShell>
      </DialogContent>
    </Dialog>
  );
}

function Tile({ label, children, className }: { label: string; children: React.ReactNode; className?: string }) {
  return (
    <div className={cn("min-w-0 rounded-xl bg-surface-2/60 px-3 py-2.5 ring-1 ring-inset ring-border", className)}>
      <p className="font-mono text-[10px] font-medium uppercase tracking-[0.06em] text-subtle">{label}</p>
      <div className="tabular mt-1 leading-tight">{children}</div>
    </div>
  );
}

/* --------------------------------- Dialogs -------------------------------- */

export function CertDialog({ holding, open, onOpenChange }: { holding: HoldingView; open: boolean; onOpenChange: (o: boolean) => void }) {
  const { certs, setCert } = useSlabCerts();
  const [value, setValue] = useState("");
  useEffect(() => {
    // Only when opened: re-running on every render would wipe what's being typed.
    if (open) setValue(certs[holding.key] ?? "");
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only when opened
  }, [open, holding.key]);
  const grade = holding.identity.grade;
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <FormShell
          title="Cert number"
          description={`The certification number printed on the ${grade?.company ?? ""} label. Used to verify the slab.`}
          onSubmit={(e) => {
            e.preventDefault();
            setCert(holding.key, value);
            toast.success(value.trim() ? "Cert number saved" : "Cert number removed");
            onOpenChange(false);
          }}
          footer={
            <Button type="submit" variant="primary" size="lg" className="w-full">
              Save
            </Button>
          }
        >
          <Field label="Cert number" htmlFor="cert-number">
            <Input id="cert-number" value={value} onChange={(e) => setValue(e.target.value.slice(0, 20))} inputMode="numeric" autoFocus />
          </Field>
        </FormShell>
      </DialogContent>
    </Dialog>
  );
}

/* ------------------------- Small fitted sheet pieces ------------------------- */
/* One look for small form sheets, like the app's SheetHeader / SheetPanel / SheetMoneyRow /
 * SheetLimeButton: a title with a round close, chips, one faint panel of rows, a quiet note and a
 * full-width lime button. The sheet fits its content. */

/** The sheet itself: a bottom sheet on phones, a small centred card on wider screens. */
export function FittedSheet({ open, onOpenChange, onSubmit, children }: { open: boolean; onOpenChange: (o: boolean) => void; onSubmit: () => void; children: React.ReactNode }) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent hideClose className="bg-[#161618] sm:max-w-[420px]" aria-describedby={undefined}>
        <form
          className="flex flex-col gap-[18px] overflow-y-auto px-5 pb-6 pt-6"
          onSubmit={(e) => {
            e.preventDefault();
            onSubmit();
          }}
        >
          {children}
        </form>
      </DialogContent>
    </Dialog>
  );
}

/** A sheet's title on the left and a round glass close on the right. */
export function SheetHeader({ title }: { title: string }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <DialogTitle className="text-[17px] font-semibold tracking-normal">{title}</DialogTitle>
      <DialogClose
        aria-label="Close"
        className="flex size-[34px] shrink-0 items-center justify-center rounded-full bg-foreground/[0.08] text-foreground ring-1 ring-inset ring-foreground/10 backdrop-blur-xl transition-colors hover:bg-foreground/[0.14]"
      >
        <X className="size-3.5" strokeWidth={2.5} />
      </DialogClose>
    </div>
  );
}

/** Rows grouped in one faint panel, divided by hairlines. */
export function SheetPanel({ children }: { children: React.ReactNode }) {
  return <div className="divide-y divide-foreground/[0.08] rounded-[18px] bg-foreground/[0.05] px-4">{children}</div>;
}

/** A label on the left and whatever it holds on the right, one row tall. */
export function SheetRow({ label, children, htmlFor }: { label: string; children: React.ReactNode; htmlFor?: string }) {
  return (
    <div className="flex min-h-[50px] items-center justify-between gap-3">
      <label htmlFor={htmlFor} className="text-[16px]">
        {label}
      </label>
      <div className="flex items-center gap-2">{children}</div>
    </div>
  );
}

/** A label and a dollar amount typed on the right. */
export function SheetMoneyRow({ label, value, onChange, id }: { label: string; value: string; onChange: (v: string) => void; id: string }) {
  return (
    <SheetRow label={label} htmlFor={id}>
      <span className="text-[16px] text-muted">$</span>
      <input
        id={id}
        inputMode="decimal"
        autoComplete="off"
        placeholder="0.00"
        value={value}
        onChange={(e) => onChange(e.target.value.replace(/[^0-9.]/g, ""))}
        className="tabular w-[96px] min-w-[4ch] bg-transparent text-right [field-sizing:content] supports-[field-sizing:content]:w-auto text-[16px] outline-none placeholder:text-subtle"
      />
    </SheetRow>
  );
}

/** A date picked on the right of a row. */
export function SheetDateRow({ label, value, onChange, id, min, max }: { label: string; value: string; onChange: (v: string) => void; id: string; min?: string; max?: string }) {
  return (
    <SheetRow label={label} htmlFor={id}>
      <input
        id={id}
        type="date"
        value={value}
        min={min}
        max={max}
        onChange={(e) => onChange(e.target.value)}
        className="tabular rounded-[10px] bg-foreground/[0.08] px-2.5 py-1.5 text-[15px] outline-none [color-scheme:dark]"
      />
    </SheetRow>
  );
}

/** A small mono label over a row of chips. */
export function SheetChips<T extends string>({ label, options, value, onChange }: { label: string; options: readonly T[]; value: T; onChange: (v: T) => void }) {
  return (
    <div>
      <p className="mb-2 font-mono text-[11px] font-medium uppercase tracking-[0.08em] text-muted">{label}</p>
      <div className="fade-row scrollbar-none -mx-5 overflow-x-auto px-5">
        <div className="flex w-max gap-2 pr-5" role="radiogroup" aria-label={label}>
          {options.map((o) => (
            <button
              key={o}
              type="button"
              role="radio"
              aria-checked={o === value}
              onClick={() => onChange(o)}
              className={cn(
                "h-9 whitespace-nowrap rounded-[13px] px-3.5 text-[14px] font-medium transition-colors",
                o === value ? "bg-foreground text-background" : "bg-foreground/[0.06] text-foreground ring-1 ring-inset ring-foreground/10 backdrop-blur-xl hover:bg-foreground/[0.1]",
              )}
            >
              {o}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

/** A quiet line under the panel. */
export function SheetNote({ children }: { children: React.ReactNode }) {
  return <p className="text-pretty text-[13px] text-muted">{children}</p>;
}

/** The full-width lime button that ends a sheet. */
export function SheetLimeButton({ children, disabled }: { children: React.ReactNode; disabled?: boolean }) {
  return (
    <button
      type="submit"
      disabled={disabled}
      className="h-[52px] w-full rounded-full bg-lime text-[16px] font-semibold text-[#0b0b0c] transition-opacity hover:opacity-90 disabled:opacity-40"
    >
      {children}
    </button>
  );
}

/** The card a sheet is about: small art, its name and one quiet line. */
function SheetCard({ product, line }: { product: HoldingView["product"]; line: string }) {
  return (
    <div className="flex items-center gap-3">
      <ProductImage product={product} size="xs" frame={false} className="h-14 w-10 shrink-0 overflow-hidden rounded-[3px]" />
      <div className="min-w-0">
        <p className="truncate text-[15px] font-semibold">{product?.name ?? "Card"}</p>
        <p className="tabular text-[13px] text-muted">{line}</p>
      </div>
    </div>
  );
}

/** Each grader's own service levels and their usual fee per card (late 2026, from public price
 * lists; the fee can still be typed over). Same list as the app's `Grading.services`. */
const SERVICES: Record<string, { name: string; fee: number }[]> = {
  PSA: [
    { name: "Value Bulk", fee: 24.99 }, { name: "Value", fee: 32.99 }, { name: "Value Plus", fee: 49.99 },
    { name: "Value Max", fee: 64.99 }, { name: "Regular", fee: 79.99 }, { name: "Express", fee: 199 }, { name: "Super Express", fee: 299 },
  ],
  BGS: [{ name: "Base", fee: 14.95 }, { name: "Standard", fee: 34.95 }, { name: "Express", fee: 79.95 }, { name: "Priority", fee: 124.95 }],
  CGC: [{ name: "Bulk", fee: 17 }, { name: "Economy", fee: 20 }, { name: "Standard", fee: 55 }, { name: "Express", fee: 100 }, { name: "WalkThrough", fee: 300 }],
  SGC: [{ name: "Standard", fee: 50 }, { name: "Expedited", fee: 150 }],
  TAG: [
    { name: "Value", fee: 29.95 }, { name: "Base", fee: 39.95 }, { name: "Standard", fee: 59.95 },
    { name: "Priority", fee: 79.95 }, { name: "Express", fee: 149.95 }, { name: "Premier", fee: 299.95 },
  ],
};
const servicesFor = (company: string) => SERVICES[company] ?? [{ name: "Standard", fee: 0 }];

/** The grades a company gives, best first (BGS and CGC have half grades from 7.5). Same as the app's `WorthCalc.grades`. */
function gradesFor(company: string): string[] {
  const whole = Array.from({ length: 10 }, (_, i) => String(i + 1));
  const list = company === "BGS" || company === "CGC" ? [...whole.slice(0, 7), "7.5", "8", "8.5", "9", "9.5", "10"] : whole;
  return list.reverse();
}

/** The fee and shipping assumed when weighing whether to grade. */
export function GradingCostsDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (o: boolean) => void }) {
  const { costs, setCosts } = useGradingCosts();
  const [fee, setFee] = useState("");
  const [shipping, setShipping] = useState("");
  useEffect(() => {
    if (!open) return;
    setFee(costs.fee.toFixed(2));
    setShipping(costs.shipping.toFixed(2));
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only when opened
  }, [open]);
  const f = parseMoney(fee);
  const s = parseMoney(shipping);
  return (
    <FittedSheet
      open={open}
      onOpenChange={onOpenChange}
      onSubmit={() => {
        if (f === null || s === null) return;
        setCosts({ fee: f, shipping: s });
        toast.success("Grading costs saved");
        onOpenChange(false);
      }}
    >
      <SheetHeader title="Grading costs" />
      <SheetPanel>
        <SheetMoneyRow id="cost-fee" label="Fee per card" value={fee} onChange={setFee} />
        <SheetMoneyRow id="cost-shipping" label="Shipping per card" value={shipping} onChange={setShipping} />
      </SheetPanel>
      <SheetNote>Used to weigh which cards are worth grading, and as the default when you send one in. Shipping both ways, with&nbsp;insurance.</SheetNote>
      <SheetLimeButton disabled={f === null || s === null}>Save</SheetLimeButton>
    </FittedSheet>
  );
}

/** Record raw copies of a card as sent off for grading. */
export function SendToGraderDialog({ holding, open, onOpenChange }: { holding: HoldingView; open: boolean; onOpenChange: (o: boolean) => void }) {
  const { today } = useStore();
  const { costs } = useGradingCosts();
  const { send } = useGradingSubmissions();
  const [company, setCompany] = useState<string>("PSA");
  const [service, setService] = useState(servicesFor("PSA")[0].name);
  const [qty, setQty] = useState(1);
  const [fee, setFee] = useState("");
  const [shipping, setShipping] = useState("");
  const [date, setDate] = useState(today);
  useEffect(() => {
    if (!open) return;
    setQty(1);
    setFee(costs.fee.toFixed(2));
    setShipping(costs.shipping.toFixed(2));
    setDate(today);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only when opened
  }, [open]);
  const f = parseMoney(fee) ?? costs.fee;
  const sh = parseMoney(shipping) ?? costs.shipping;
  const owned = Math.max(1, Math.floor(holding.quantity));
  return (
    <FittedSheet
      open={open}
      onOpenChange={onOpenChange}
      onSubmit={() => {
        if (!date || date > today) return;
        send({ productId: holding.identity.productId, printing: holding.identity.printing, condition: holding.identity.condition, company, service, quantity: qty, fee: f, shipping: sh, sentOn: date });
        toast.success(`Marked as sent to ${company}`, { description: "Track it on the Grading page." });
        onOpenChange(false);
      }}
    >
      <SheetHeader title="Send for grading" />
      <SheetCard product={holding.product} line={`Raw ${moneyWhole(holding.price)}`} />
      <SheetChips
        label="Grader"
        options={GRADERS}
        value={company as (typeof GRADERS)[number]}
        onChange={(c) => {
          // A new grader starts on its cheapest service, with that service's usual fee.
          setCompany(c);
          const first = servicesFor(c)[0];
          setService(first.name);
          if (first.fee > 0) setFee(first.fee.toFixed(2));
        }}
      />
      <SheetChips
        label={`${company} service`}
        options={servicesFor(company).map((x) => x.name)}
        value={service}
        onChange={(sv) => {
          setService(sv);
          const usual = servicesFor(company).find((x) => x.name === sv)?.fee;
          if (usual) setFee(usual.toFixed(2));
        }}
      />
      <SheetPanel>
        {owned > 1 && (
          <SheetRow label="Copies">
            <span className="tabular text-[16px] text-muted">
              {qty} of {owned}
            </span>
            <span className="flex overflow-hidden rounded-[10px] bg-foreground/[0.08]">
              <button type="button" aria-label="Fewer copies" disabled={qty <= 1} onClick={() => setQty((q) => Math.max(1, q - 1))} className="flex h-8 w-9 items-center justify-center disabled:opacity-30">
                <Minus className="size-4" />
              </button>
              <button type="button" aria-label="More copies" disabled={qty >= owned} onClick={() => setQty((q) => Math.min(owned, q + 1))} className="flex h-8 w-9 items-center justify-center border-l border-foreground/10 disabled:opacity-30">
                <Plus className="size-4" />
              </button>
            </span>
          </SheetRow>
        )}
        <SheetMoneyRow id="grade-fee" label="Fee per card" value={fee} onChange={setFee} />
        <SheetMoneyRow id="grade-shipping" label="Shipping per card" value={shipping} onChange={setShipping} />
        <SheetDateRow id="grade-date" label="Sent" value={date} max={today} onChange={setDate} />
      </SheetPanel>
      <SheetNote>It stays in your collection raw until it comes&nbsp;back.</SheetNote>
      <SheetLimeButton disabled={!date || date > today}>Mark as sent</SheetLimeButton>
    </FittedSheet>
  );
}

/** A submission came back: pick the grade and turn the raw card into a slab. */
export function ReturnDialog({ submission, holding, open, onOpenChange }: { submission: GradingSubmission; holding: HoldingView | undefined; open: boolean; onOpenChange: (o: boolean) => void }) {
  const { today, data } = useStore();
  const { complete } = useGradingSubmissions();
  const [grade, setGrade] = useState("10");
  const [date, setDate] = useState(today);
  const [saving, setSaving] = useState(false);
  useEffect(() => {
    if (!open) return;
    setGrade("10");
    setDate(today);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only when opened
  }, [open]);
  const product = data.products[submission.productId];
  const valid = grade.trim() !== "" && Boolean(date) && date <= today && date >= submission.sentOn;
  return (
    <FittedSheet
      open={open}
      onOpenChange={onOpenChange}
      onSubmit={async () => {
        if (!valid || saving) return;
        setSaving(true);
        try {
          await complete(submission, { company: submission.company, grade: grade.trim() }, holding, date);
          toast.success(`${submission.company} ${grade.trim()} added to your collection`);
          onOpenChange(false);
        } catch (err) {
          toast.error("Couldn't save", { description: err instanceof Error ? err.message : undefined });
        } finally {
          setSaving(false);
        }
      }}
    >
      <SheetHeader title="It's back" />
      <p className="truncate text-[15px] font-semibold">{product?.name ?? "Card"}</p>
      <SheetChips label={`${submission.company} grade`} options={gradesFor(submission.company)} value={grade} onChange={setGrade} />
      <SheetPanel>
        <SheetDateRow id="return-date" label="Returned" value={date} min={submission.sentOn} max={today} onChange={setDate} />
      </SheetPanel>
      <SheetNote>
        {holding
          ? `The raw copies move into a ${submission.company} slab at what they cost you, plus the grading fee and shipping (${money(submission.fee + submission.shipping)} per card).`
          : `The raw card is no longer in your collection, so the slab is added at the grading cost only (${money(submission.fee + submission.shipping)} per card).`}
      </SheetNote>
      <SheetLimeButton disabled={!valid || saving}>{saving ? "Saving…" : "Save"}</SheetLimeButton>
    </FittedSheet>
  );
}

/** Raw holdings currently at a grader, keyed by holding key. */
export function useAtGrader() {
  const { submissions } = useGradingSubmissions();
  return useMemo(() => {
    const m = new Map<string, number>();
    for (const s of submissions) {
      if (s.status !== "sent") continue;
      const key = holdingKey({ productId: s.productId, printing: s.printing, condition: s.condition, grade: null });
      m.set(key, (m.get(key) ?? 0) + s.quantity);
    }
    return m;
  }, [submissions]);
}

export function formatSent(s: GradingSubmission, today: string) {
  const days = daysBetween(s.sentOn, today);
  return `${s.company} ${s.service} · sent ${formatDate(s.sentOn)}${days > 0 ? ` · ${days} day${days === 1 ? "" : "s"} ago` : ""}`;
}

/** Where an automatic slab value comes from: the sample curve, eBay sales, or nowhere yet. */
export function slabSourceLabel(h: HoldingView) {
  if (gradedSampleFor(h.identity.productId)) return "Graded market · sample";
  return h.price === null ? "No recent eBay sales · set your value" : "eBay sold median";
}

/**
 * How many of a grade sell a year: from the card's recent eBay sales (30 days,
 * scaled to a year) when this device has them, else the sample estimate.
 */
function salesPerYear(productId: string, printing: string | null, grade: Grade, raw: number) {
  const e = gradedSampleFor(productId) ? null : cachedEbay(productId, printing)?.value;
  return e ? (e.graded[gradeLabel(grade)]?.count ?? 0) * 12 : sampleSalesPerYear(productId, grade, raw);
}
