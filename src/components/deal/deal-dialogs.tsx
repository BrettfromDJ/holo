"use client";

import { ChevronRight, Minus, Plus } from "lucide-react";
import { useState } from "react";
import { ProductImage } from "@/components/product/product-image";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { Switch } from "@/components/ui/switch";
import { ROUND_STEPS, lineRate, parkedDealName, roundStep, withTypedMarket, type DealKind, type DealRates } from "@/lib/deal";
import { money, signedMoney } from "@/lib/format";
import { cn } from "@/lib/utils";
import { RoundClose } from "./deal-card";
import { shortName, type DealItem } from "./deal-picker";
import { KIND_COLOR, kindButton } from "./deal-types";

/** "$1,234.50" or "12" typed: the number, or null when it isn't one. */
export function parseMoney(text: string): number | null {
  const t = text.replace(/[^0-9.]/g, "");
  if (t === "") return null;
  const n = Number(t);
  return Number.isFinite(n) ? n : null;
}

/** Our small fitted dialog: a title and round close, then its content (the app's SheetHeader sheets). */
export function SheetDialog({ open, onOpenChange, title, line, children, className }: { open: boolean; onOpenChange: (o: boolean) => void; title: React.ReactNode; line?: React.ReactNode; children: React.ReactNode; className?: string }) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent hideClose className={cn("bg-[#161618] sm:max-w-[420px]", className)}>
        <div className="min-h-0 overflow-y-auto px-5 pb-6 pt-6">
          <div className="flex items-start gap-3">
            <div className="min-w-0 flex-1">
              <DialogTitle className="font-display text-[22px] leading-tight tracking-[-0.02em]">{title}</DialogTitle>
              {line ? <DialogDescription className="mt-1 text-[13px] text-muted">{line}</DialogDescription> : <DialogDescription className="sr-only">{typeof title === "string" ? title : "Dialog"}</DialogDescription>}
            </div>
            <RoundClose onClick={() => onOpenChange(false)} />
          </div>
          <div className="mt-4">{children}</div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

/** A full-width button in the deal kind's colour (lime by default). */
export function KindButton({ kind = "sell", className, ...props }: React.ButtonHTMLAttributes<HTMLButtonElement> & { kind?: DealKind }) {
  return <button type="button" {...props} className={cn("btn-3d h-12 w-full rounded-full text-[16px] font-semibold disabled:opacity-45", KIND_COLOR[kind].btn3d, className)} style={kindButton(kind)} />;
}

/** A big number you can type, with a round − on the left and + on the right (the app's StepField). */
function StepField({ value, onChange, step, min, max, prefix, suffix, decimals, label }: { value: string; onChange: (v: string) => void; step: number; min: number; max: number; prefix?: string; suffix?: string; decimals: number; label: string }) {
  const current = parseMoney(value) ?? 0;
  const nudge = (by: number) => {
    const next = Math.min(max, Math.max(min, by > 0 ? Math.floor(current / step) * step + step : Math.ceil(current / step) * step - step));
    return next;
  };
  const btn = (by: number) => {
    const next = nudge(by);
    return (
      <button type="button" aria-label={by > 0 ? `Up ${step}` : `Down ${step}`} disabled={next === current} onClick={() => onChange(decimals === 0 ? String(Math.round(next)) : next.toFixed(decimals))} className="flex size-11 shrink-0 items-center justify-center rounded-full bg-white/[0.08] text-white hover:bg-white/[0.12] disabled:opacity-40">
        {by > 0 ? <Plus className="size-4" /> : <Minus className="size-4" />}
      </button>
    );
  };
  return (
    <div className="flex h-[70px] items-center gap-2 rounded-2xl bg-white/[0.05] px-3 ring-1 ring-inset ring-white/[0.08]">
      {btn(-step)}
      <label className="tabular flex min-w-0 flex-1 items-baseline justify-center gap-1 font-display text-[34px] leading-none">
        {prefix && <span className="text-muted">{prefix}</span>}
        <input value={value} onChange={(e) => onChange(e.target.value.replace(/[^0-9.]/g, ""))} onFocus={(e) => e.target.select()} inputMode={decimals === 0 ? "numeric" : "decimal"} aria-label={label} placeholder="0" className="w-[5ch] min-w-0 bg-transparent text-center outline-none placeholder:text-subtle" style={{ width: `${Math.max(1, value.length) * 0.62 + 0.1}em` }} />
        {suffix && <span className="text-muted">{suffix}</span>}
      </label>
      {btn(step)}
    </div>
  );
}

/** A label and a $ field on one line, inside a panel (the app's SheetMoneyRow). */
function MoneyRow({ title, value, onChange }: { title: string; value: string; onChange: (v: string) => void }) {
  return (
    <label className="flex min-h-[50px] items-center justify-between gap-3">
      <span className="text-[16px]">{title}</span>
      <span className="tabular flex items-baseline gap-0.5 text-[16px] text-muted">
        $<input value={value} onChange={(e) => onChange(e.target.value.replace(/[^0-9.]/g, ""))} onFocus={(e) => e.target.select()} inputMode="decimal" aria-label={title} placeholder="0.00" className="bg-transparent text-right text-white outline-none placeholder:text-subtle" style={{ width: `${Math.max(4, value.length) * 0.62 + 0.2}em` }} />
      </span>
    </label>
  );
}

const panelClass = "rounded-2xl bg-white/[0.05] px-4 ring-1 ring-inset ring-white/[0.08]";
const divider = <div className="h-px bg-white/[0.08]" />;

/**
 * Click a card in the deal (the app's DealCardSheet): its rate as a percentage or a fixed price,
 * the market price (with Reset to catalog price once changed by hand), quantity, what you paid
 * (read from your collection, else typed), the profit, Reset to deal rate, Save changes, Remove card.
 */
export function DealCardDialog({ item, rate, selling, collectionCost, onSave, onRemove, onClose }: { item: DealItem | null; rate: number; selling: boolean; collectionCost: number | null; onSave: (i: DealItem) => void; onRemove: (i: DealItem) => void; onClose: () => void }) {
  return (
    <Dialog open={item !== null} onOpenChange={(o) => !o && onClose()}>
      <DialogContent hideClose className="bg-[#161618] sm:max-w-[440px]">
        {item && <CardForm key={item.key} item={item} rate={rate} selling={selling} collectionCost={collectionCost} onSave={onSave} onRemove={onRemove} onClose={onClose} />}
      </DialogContent>
    </Dialog>
  );
}

function CardForm({ item, rate, selling, collectionCost, onSave, onRemove, onClose }: { item: DealItem; rate: number; selling: boolean; collectionCost: number | null; onSave: (i: DealItem) => void; onRemove: (i: DealItem) => void; onClose: () => void }) {
  const [mode, setMode] = useState<"percent" | "fixed">(item.price !== null ? "fixed" : "percent");
  const [value, setValue] = useState(item.price !== null ? item.price.toFixed(2) : String(Math.round(lineRate(item, rate) * 100)));
  const [market, setMarket] = useState(item.market !== null ? item.market.toFixed(2) : "");
  const [qty, setQty] = useState(item.qty);
  const [paid, setPaid] = useState(item.cost !== null && item.cost !== undefined ? item.cost.toFixed(2) : "");
  const marketValue = parseMoney(market) ?? item.market;
  const v = parseMoney(value);
  const unit = v === null ? null : mode === "fixed" ? v : marketValue === null ? null : (marketValue * v) / 100;
  const workedOut = unit === null ? "—" : mode === "percent" ? money(unit) : marketValue && marketValue > 0 ? `${Math.round((unit / marketValue) * 100)}%` : "—";
  const catalog = item.catalogMarket ?? item.market;
  const typedMarket = parseMoney(market);
  const restore = !item.custom && catalog !== null && typedMarket !== null && Math.abs(typedMarket - catalog) > 0.004 ? catalog : null;
  const cost = collectionCost ?? (parseMoney(paid) === null ? null : parseMoney(paid)! * qty);
  const profit = selling && unit !== null && cost !== null ? unit * qty - cost : null;
  const switchMode = (m: "percent" | "fixed") => {
    if (m === mode) return;
    setMode(m);
    if (m === "fixed") setValue(unit === null ? "" : unit.toFixed(2));
    else if (unit !== null && marketValue && marketValue > 0) setValue(String(Math.round((unit / marketValue) * 100)));
  };
  const withMarket = (c: DealItem) => withTypedMarket(c, typedMarket);
  const save = () => {
    let c: DealItem = { ...item, qty };
    if (selling && collectionCost === null && !item.custom) c.cost = parseMoney(paid);
    c = withMarket(c);
    if (v !== null) {
      if (mode === "fixed") c = { ...c, price: v, rate: null };
      else {
        const r = v / 100;
        c = { ...c, price: null, rate: Math.abs(r - rate) < 0.0001 && (item.rate === null || item.rate === undefined) && item.price === null ? null : r };
      }
    }
    onSave(c);
    onClose();
  };
  const maxQty = Math.max(1, item.maxQty ?? 999);
  return (
    <div className="min-h-0 space-y-4 overflow-y-auto px-5 pb-6 pt-6">
      <div className="flex items-center gap-3">
        <ProductImage product={item.product} size="xs" className="h-14 w-10 shrink-0 rounded-[3px]" />
        <div className="min-w-0 flex-1">
          <DialogTitle className="truncate text-[18px] font-semibold">{shortName(item.product)}</DialogTitle>
          <DialogDescription className="truncate text-[13px] text-muted">{[item.product.setName, item.product.number].filter(Boolean).join(" · ") || (item.custom ? "Custom item" : "")}</DialogDescription>
          {!item.custom && (
            <a href={`/product/${encodeURIComponent(item.product.id)}`} target="_blank" rel="noreferrer" className="mt-0.5 inline-flex items-center gap-0.5 text-[13px] font-medium text-[var(--lime)] hover:underline">
              View card <ChevronRight className="size-3" />
            </a>
          )}
        </div>
        <RoundClose onClick={onClose} />
      </div>
      <div className="grid grid-cols-2 gap-2">
        {(["percent", "fixed"] as const).map((m) => (
          <button key={m} type="button" aria-pressed={mode === m} onClick={() => switchMode(m)} className={cn("h-10 rounded-[13px] text-[14px] font-semibold transition-colors", mode === m ? "bg-white text-[#0b0b0c]" : "glass-stat text-white hover:bg-white/[0.08]")}>
            {m === "percent" ? "Percentage" : "Fixed price"}
          </button>
        ))}
      </div>
      <div className="space-y-1.5 text-center">
        <p className="text-[13px] text-muted">{mode === "percent" ? "Agreed rate" : "Agreed price per card"}</p>
        {mode === "percent" ? <StepField label="Agreed rate" value={value} onChange={setValue} step={1} min={1} max={200} suffix="%" decimals={0} /> : <StepField label="Agreed price per card" value={value} onChange={setValue} step={1} min={0} max={1_000_000} prefix="$" decimals={2} />}
      </div>
      <div className="flex items-center justify-between">
        <span className="text-[14px] text-muted">{mode === "percent" ? "Agreed price per card" : "Share of market"}</span>
        <span className="tabular text-[15px] font-semibold">{workedOut}</span>
      </div>
      <div className={panelClass}>
        <MoneyRow title="Market price" value={market} onChange={setMarket} />
        {restore !== null && (
          <button type="button" onClick={() => setMarket(restore.toFixed(2))} className="block pb-3 text-left text-[13px] font-medium text-[var(--lime)] hover:underline">
            Reset to catalog price ({money(restore)})
          </button>
        )}
        {divider}
        <div className="flex min-h-[50px] items-center justify-between">
          <span className="text-[16px]">Quantity</span>
          <span className="flex items-center gap-3">
            <span className="tabular text-[16px] text-muted">{qty}</span>
            <span className="flex overflow-hidden rounded-lg bg-white/[0.08]">
              <button type="button" aria-label="Fewer" disabled={qty <= 1} onClick={() => setQty((n) => Math.max(1, n - 1))} className="flex h-8 w-11 items-center justify-center hover:bg-white/[0.06] disabled:opacity-35">
                <Minus className="size-3.5" />
              </button>
              <span className="my-1.5 w-px bg-white/15" />
              <button type="button" aria-label="More" disabled={qty >= maxQty} onClick={() => setQty((n) => Math.min(maxQty, n + 1))} className="flex h-8 w-11 items-center justify-center hover:bg-white/[0.06] disabled:opacity-35">
                <Plus className="size-3.5" />
              </button>
            </span>
          </span>
        </div>
        {selling && !item.custom && (
          <>
            {divider}
            {collectionCost !== null ? (
              <div className="flex min-h-[50px] items-center justify-between">
                <span className="text-[16px]">You paid</span>
                <span className="tabular text-[16px] text-muted">{money(collectionCost)}</span>
              </div>
            ) : (
              <MoneyRow title="You paid each" value={paid} onChange={setPaid} />
            )}
          </>
        )}
      </div>
      {profit !== null && (
        <div className="flex items-center justify-between">
          <span className="text-[14px] text-muted">Profit</span>
          <span className={cn("tabular text-[15px] font-semibold", profit >= 0 ? "text-up" : "text-down")}>{signedMoney(profit)}</span>
        </div>
      )}
      {(item.price !== null || (item.rate !== null && item.rate !== undefined)) && (
        <button
          type="button"
          onClick={() => {
            onSave(withMarket({ ...item, price: null, rate: null, qty }));
            onClose();
          }}
          className="block w-full text-center text-[14px] font-medium text-muted hover:text-foreground"
        >
          Reset to deal rate ({Math.round(rate * 100)}%)
        </button>
      )}
      <KindButton onClick={save}>Save changes</KindButton>
      <button
        type="button"
        onClick={() => {
          onRemove(item);
          onClose();
        }}
        className="block w-full text-center text-[14px] font-medium text-[var(--plan-pink)] hover:underline"
      >
        Remove card
      </button>
    </div>
  );
}

/** The ⋯ beside the rate chips: type any rate (the app's DealRateSheet "Set default rate"). */
export function RateDialog({ open, onOpenChange, rate, onApply }: { open: boolean; onOpenChange: (o: boolean) => void; rate: number; onApply: (r: number) => void }) {
  return (
    <SheetDialog open={open} onOpenChange={onOpenChange} title="Set default rate" line="Only cards without their own price will update.">
      <RateForm rate={rate} onApply={onApply} onDone={() => onOpenChange(false)} />
    </SheetDialog>
  );
}

function RateForm({ rate, onApply, onDone }: { rate: number; onApply: (r: number) => void; onDone: () => void }) {
  const [value, setValue] = useState(String(Math.round(rate * 100)));
  const n = parseMoney(value);
  const ok = n !== null && n >= 30 && n <= 150;
  return (
    <div className="space-y-4">
      <StepField label="Rate" value={value} onChange={setValue} step={1} min={30} max={150} suffix="%" decimals={0} />
      <KindButton
        disabled={!ok}
        onClick={() => {
          if (ok) onApply(n / 100);
          onDone();
        }}
      >
        Apply rate
      </KindButton>
    </div>
  );
}

/** Type an amount (the agreed cash, the agreed market value), with an optional second action. */
export function AmountDialog({ open, onOpenChange, title, line, initial, submit, onSet, secondary }: { open: boolean; onOpenChange: (o: boolean) => void; title: string; line: string; initial: number; submit: string; onSet: (n: number) => void; secondary?: { label: string; onClick: () => void } | null }) {
  return (
    <SheetDialog open={open} onOpenChange={onOpenChange} title={title} line={line}>
      <AmountForm title={title} initial={initial} submit={submit} onSet={onSet} secondary={secondary} onDone={() => onOpenChange(false)} />
    </SheetDialog>
  );
}

function AmountForm({ title, initial, submit, onSet, secondary, onDone }: { title: string; initial: number; submit: string; onSet: (n: number) => void; secondary?: { label: string; onClick: () => void } | null; onDone: () => void }) {
  const [text, setText] = useState(initial.toFixed(2));
  return (
    <form
      className="space-y-3"
      onSubmit={(e) => {
        e.preventDefault();
        const n = parseMoney(text);
        if (n !== null) onSet(n);
        onDone();
      }}
    >
      <span className="relative block">
        <span className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2 text-[15px] text-subtle">$</span>
        <input autoFocus inputMode="decimal" value={text} onChange={(e) => setText(e.target.value.replace(/[^0-9.]/g, ""))} onFocus={(e) => e.target.select()} aria-label={title} className="tabular h-12 w-full rounded-2xl bg-white/[0.06] pl-8 pr-4 text-[17px] outline-none ring-1 ring-inset ring-white/[0.08] focus:ring-white/25" />
      </span>
      <KindButton type="submit">{submit}</KindButton>
      {secondary && (
        <button
          type="button"
          onClick={() => {
            secondary.onClick();
            onDone();
          }}
          className="block w-full pt-1 text-center text-[14px] font-medium text-muted hover:text-foreground"
        >
          {secondary.label}
        </button>
      )}
    </form>
  );
}

/** Name the deal (Rename deal), or name it while saving it for later. */
export function NameDialog({ open, onOpenChange, title, line, initial, submit, onSave }: { open: boolean; onOpenChange: (o: boolean) => void; title: string; line?: string; initial: string; submit: string; onSave: (name: string) => void }) {
  return (
    <SheetDialog open={open} onOpenChange={onOpenChange} title={title} line={line}>
      <NameForm initial={initial} submit={submit} onSave={onSave} onDone={() => onOpenChange(false)} />
    </SheetDialog>
  );
}

function NameForm({ initial, submit, onSave, onDone }: { initial: string; submit: string; onSave: (name: string) => void; onDone: () => void }) {
  const [name, setName] = useState(initial);
  return (
    <form
      className="space-y-3"
      onSubmit={(e) => {
        e.preventDefault();
        onSave(name.trim());
        onDone();
      }}
    >
      <input autoFocus value={name} onChange={(e) => setName(e.target.value)} placeholder={submit === "Save for later" ? parkedDealName(new Date()) : "Untitled deal"} aria-label="Name" maxLength={80} className="h-12 w-full rounded-2xl bg-white/[0.06] px-4 text-[16px] outline-none ring-1 ring-inset ring-white/[0.08] placeholder:text-subtle focus:ring-white/25" />
      <KindButton type="submit">{submit}</KindButton>
    </form>
  );
}

/** A plain centred question with Cancel and a pink action (switching kind, leaving a deal). */
export function ConfirmDialog({ open, onOpenChange, title, line, actions }: { open: boolean; onOpenChange: (o: boolean) => void; title: string; line?: string; actions: { label: string; onClick: () => void; danger?: boolean }[] }) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent hideClose className="bg-[#161618] sm:top-[30vh] sm:max-w-[360px]">
        <div className="px-5 pb-5 pt-6 text-center">
          <DialogTitle className="text-balance text-[17px] font-semibold">{title}</DialogTitle>
          {line ? <DialogDescription className="mt-1.5 text-[14px] text-muted">{line}</DialogDescription> : <DialogDescription className="sr-only">{title}</DialogDescription>}
          <div className="mt-5 space-y-2">
            {actions.map((a) => (
              <button
                key={a.label}
                type="button"
                onClick={() => {
                  onOpenChange(false);
                  a.onClick();
                }}
                className={cn("h-11 w-full rounded-full text-[15px] font-semibold", a.danger ? "bg-[color-mix(in_srgb,var(--plan-pink)_14%,transparent)] text-[var(--plan-pink)] ring-1 ring-inset ring-[color-mix(in_srgb,var(--plan-pink)_30%,transparent)]" : "glass-stat text-white hover:bg-white/[0.08]")}
              >
                {a.label}
              </button>
            ))}
            <button type="button" onClick={() => onOpenChange(false)} className="h-10 w-full text-[14px] font-medium text-muted hover:text-foreground">
              Cancel
            </button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

/** Deal settings: the default rates and how a deal behaves. Shared with the app ("deal-rates"). */
export function SettingsDialog({ open, onOpenChange, rates, onSave }: { open: boolean; onOpenChange: (o: boolean) => void; rates: DealRates; onSave: (r: DealRates) => void }) {
  const rows: { key: "buy" | "trade" | "sell"; label: string; hint: string }[] = [
    { key: "buy", label: "Buying", hint: "What you pay for cards you buy outright" },
    { key: "trade", label: "Trade-in", hint: "What you credit for cards taken in on trade" },
    { key: "sell", label: "Selling", hint: "What you charge for cards going out" },
  ];
  return (
    <SheetDialog open={open} onOpenChange={onOpenChange} title="Deal settings" line="Rates as a share of market. Every new deal starts here." className="sm:max-w-[440px]">
      <div className="space-y-5">
        {rows.map((r) => (
          <div key={r.key}>
            <div className="flex items-baseline justify-between">
              <span className="text-[15px] font-medium">{r.label}</span>
              <span className="tabular font-display text-[22px]">{Math.round(rates[r.key] * 100)}%</span>
            </div>
            <p className="text-[12px] text-muted">{r.hint}</p>
            <input type="range" min={40} max={120} step={1} value={Math.round(rates[r.key] * 100)} onChange={(e) => onSave({ ...rates, [r.key]: Number(e.target.value) / 100 })} aria-label={`${r.label} rate`} className="deal-range mt-2 w-full" />
          </div>
        ))}
        <div>
          <span className="block text-[15px] font-medium">Round up to the nearest</span>
          <span className="block text-[12px] text-muted">What Round up on the deal card rounds to.</span>
          <div role="radiogroup" aria-label="Round up to the nearest" className="mt-2 flex flex-wrap gap-1.5">
            {ROUND_STEPS.map((step) => {
              const on = roundStep(rates) === step;
              return (
                <button key={step} type="button" role="radio" aria-checked={on} onClick={() => onSave({ ...rates, roundStep: step })} className={cn("tabular h-9 rounded-[13px] px-3.5 text-[13px] font-semibold transition-colors", on ? "bg-white text-[#0b0b0c]" : "glass-stat text-white hover:bg-white/[0.08]")}>
                  ${step}
                </button>
              );
            })}
          </div>
        </div>
        <label className="flex items-center justify-between gap-4">
          <span>
            <span className="block text-[15px] font-medium">Add what comes in to my collection</span>
            <span className="block text-[12px] text-muted">Cards you buy or trade for are recorded when the deal closes.</span>
          </span>
          <Switch checked={rates.addIncoming ?? true} onCheckedChange={(on) => onSave({ ...rates, addIncoming: on })} />
        </label>
        <label className="flex items-center justify-between gap-4">
          <span>
            <span className="block text-[15px] font-medium">Ask what I paid for things not in Corodex</span>
            <span className="block text-[12px] text-muted">With it, they&apos;re recorded properly and their profit is known.</span>
          </span>
          <Switch checked={rates.askCost ?? true} onCheckedChange={(on) => onSave({ ...rates, askCost: on })} />
        </label>
      </div>
    </SheetDialog>
  );
}
