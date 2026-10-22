"use client";

import { Loader2, MoreHorizontal, Pencil, Trash2 } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input, Textarea } from "@/components/ui/input";
import { Segmented } from "@/components/ui/segmented";
import { Delta } from "@/components/product/delta";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { effectiveTransactions } from "@/lib/finance/ledger";
import type { HoldingView } from "@/lib/finance/portfolio";
import { formatDate, money, signedMoney } from "@/lib/format";
import { useStore } from "@/lib/store/collection-store";
import type { Transaction } from "@/lib/types";
import { Field, MoneyInput, Stepper, SummaryRow, parseMoney } from "./fields";

/** Cost of the first `qty` units under FIFO, for previewing a sale. */
function fifoCost(holding: HoldingView, qty: number): number {
  let remaining = qty;
  let cost = 0;
  for (const lot of holding.lots) {
    if (remaining <= 0) break;
    const take = Math.min(lot.quantity, remaining);
    cost += take * lot.unitCost;
    remaining -= take;
  }
  return cost;
}

function FormShell({ title, description, children, footer, onSubmit }: { title: string; description?: string; children: React.ReactNode; footer: React.ReactNode; onSubmit: (e: React.FormEvent) => void }) {
  return (
    <form onSubmit={onSubmit} className="flex min-h-0 flex-1 flex-col">
      <DialogHeader>
        <DialogTitle>{title}</DialogTitle>
        {description ? <DialogDescription>{description}</DialogDescription> : <DialogDescription className="sr-only">{title}</DialogDescription>}
      </DialogHeader>
      <div className="flex-1 space-y-4 overflow-y-auto px-6 py-4">{children}</div>
      <div className="border-t border-border px-6 pb-6 pt-4">{footer}</div>
    </form>
  );
}

export function SaleDialog({ holding, open, onOpenChange }: { holding: HoldingView; open: boolean; onOpenChange: (o: boolean) => void }) {
  const { addTransaction, today } = useStore();
  const [qty, setQty] = useState(1);
  const [mode, setMode] = useState<"unit" | "lot">("unit");
  const [price, setPrice] = useState("");
  const [date, setDate] = useState(today);
  const [fees, setFees] = useState("");
  const [shipping, setShipping] = useState("");
  const [notes, setNotes] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (open) {
      setQty(1);
      setMode("unit");
      setPrice(holding.price !== null ? holding.price.toFixed(2) : "");
      setDate(today);
      setFees("");
      setShipping("");
      setNotes("");
    }
  }, [open, holding.price, today]);

  const entered = parseMoney(price);
  const unit = entered === null ? null : mode === "unit" ? entered : entered / qty;
  const gross = unit === null ? null : unit * qty;
  const costs = (parseMoney(fees) ?? 0) + (parseMoney(shipping) ?? 0);
  const proceeds = gross === null ? null : gross - costs;
  const basis = fifoCost(holding, qty);
  const gain = proceeds === null ? null : proceeds - basis;
  const valid = qty >= 1 && qty <= holding.quantity && unit !== null && date <= today;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!valid || unit === null) return;
    setSaving(true);
    try {
      await addTransaction({
        ...holding.identity,
        type: "sale",
        date,
        quantity: qty,
        unitPrice: unit,
        fees: parseMoney(fees) ?? 0,
        shipping: parseMoney(shipping) ?? 0,
        tax: 0,
        notes: notes.trim() || null,
      });
      toast.success(`Recorded sale of ${qty} × ${holding.product?.name ?? "item"}`, { description: `Realized ${signedMoney(gain)}` });
      onOpenChange(false);
    } catch (err) {
      toast.error("Couldn't record sale", { description: err instanceof Error ? err.message : undefined });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <FormShell
          title="Record sale"
          description={`${holding.product?.name ?? "Item"} · ${holding.quantity} owned · cost basis uses FIFO`}
          onSubmit={submit}
          footer={
            <>
              <div className="space-y-1.5">
                <SummaryRow label="Net proceeds" value={money(proceeds)} />
                <SummaryRow label="FIFO cost basis" value={money(basis)} />
                <div className="flex items-center justify-between text-[14px] font-semibold">
                  <span>Realized gain</span>
                  <Delta value={gain} ratio={gain !== null && basis > 0 ? gain / basis : null} />
                </div>
              </div>
              <Button type="submit" variant="primary" size="lg" className="mt-4 w-full" disabled={!valid || saving}>
                {saving && <Loader2 className="animate-spin" />}
                Record sale
              </Button>
            </>
          }
        >
          <div className="grid grid-cols-2 gap-3">
            <Field label="Quantity" hint={`of ${holding.quantity}`}>
              <Stepper value={qty} onChange={setQty} max={holding.quantity} label="Quantity sold" />
            </Field>
            <Field label="Sale date" htmlFor="sale-date">
              <Input id="sale-date" type="date" value={date} max={today} onChange={(e) => setDate(e.target.value)} />
            </Field>
          </div>
          <Field
            label={mode === "unit" ? "Sale price per unit" : "Total sale price"}
            htmlFor="sale-price"
            hint={
              <Segmented
                ariaLabel="Price entry"
                size="sm"
                value={mode}
                onChange={setMode}
                options={[
                  { value: "unit", label: "Per unit" },
                  { value: "lot", label: "Total" },
                ]}
              />
            }
          >
            <MoneyInput id="sale-price" value={price} onChange={setPrice} />
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Selling fees" htmlFor="sale-fees">
              <MoneyInput id="sale-fees" value={fees} onChange={setFees} />
            </Field>
            <Field label="Shipping paid" htmlFor="sale-ship">
              <MoneyInput id="sale-ship" value={shipping} onChange={setShipping} />
            </Field>
          </div>
          <Field label="Notes" htmlFor="sale-notes">
            <Textarea id="sale-notes" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Optional" />
          </Field>
        </FormShell>
      </DialogContent>
    </Dialog>
  );
}

export function AdjustDialog({ holding, open, onOpenChange }: { holding: HoldingView; open: boolean; onOpenChange: (o: boolean) => void }) {
  const { addTransaction, today } = useStore();
  const [direction, setDirection] = useState<"remove" | "add">("remove");
  const [qty, setQty] = useState(1);
  const [cost, setCost] = useState("0");
  const [date, setDate] = useState(today);
  const [notes, setNotes] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (open) {
      setDirection("remove");
      setQty(1);
      setCost("0");
      setDate(today);
      setNotes("");
    }
  }, [open, today]);

  const valid = qty >= 1 && (direction === "add" || qty <= holding.quantity) && notes.trim().length > 0;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!valid) return;
    setSaving(true);
    try {
      await addTransaction({
        ...holding.identity,
        type: "adjustment",
        date,
        quantity: direction === "add" ? qty : -qty,
        unitPrice: direction === "add" ? (parseMoney(cost) ?? 0) : 0,
        fees: 0,
        shipping: 0,
        tax: 0,
        notes: notes.trim(),
      });
      toast.success("Quantity adjusted");
      onOpenChange(false);
    } catch (err) {
      toast.error("Couldn't save adjustment", { description: err instanceof Error ? err.message : undefined });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <FormShell
          title="Adjust quantity"
          description="For items opened, lost, gifted or pulled. Removals write off FIFO cost basis as a realized loss."
          onSubmit={submit}
          footer={
            <Button type="submit" variant="primary" size="lg" className="w-full" disabled={!valid || saving}>
              {saving && <Loader2 className="animate-spin" />}
              Save adjustment
            </Button>
          }
        >
          <Segmented
            ariaLabel="Adjustment direction"
            value={direction}
            onChange={setDirection}
            options={[
              { value: "remove", label: "Remove units" },
              { value: "add", label: "Add units" },
            ]}
          />
          <div className="grid grid-cols-2 gap-3">
            <Field label="Quantity">
              <Stepper value={qty} onChange={setQty} max={direction === "remove" ? holding.quantity : 9999} label="Adjustment quantity" />
            </Field>
            <Field label="Date" htmlFor="adj-date">
              <Input id="adj-date" type="date" value={date} max={today} onChange={(e) => setDate(e.target.value)} />
            </Field>
          </div>
          {direction === "add" && (
            <Field label="Cost basis per unit" hint="0 for gifts or pulls" htmlFor="adj-cost">
              <MoneyInput id="adj-cost" value={cost} onChange={setCost} />
            </Field>
          )}
          <Field label="Reason" htmlFor="adj-notes">
            <Input id="adj-notes" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder={direction === "remove" ? "e.g. Opened for the binder" : "e.g. Pulled from a pack"} />
          </Field>
        </FormShell>
      </DialogContent>
    </Dialog>
  );
}

export function CorrectionDialog({ tx, open, onOpenChange }: { tx: Transaction | null; open: boolean; onOpenChange: (o: boolean) => void }) {
  const { addTransaction, today } = useStore();
  const [qty, setQty] = useState(1);
  const [price, setPrice] = useState("");
  const [date, setDate] = useState(today);
  const [fees, setFees] = useState("");
  const [shipping, setShipping] = useState("");
  const [tax, setTax] = useState("");
  const [reason, setReason] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (open && tx) {
      setQty(Math.abs(tx.quantity));
      setPrice(String(tx.unitPrice));
      setDate(tx.date);
      setFees(String(tx.fees || ""));
      setShipping(String(tx.shipping || ""));
      setTax(String(tx.tax || ""));
      setReason("");
    }
  }, [open, tx]);

  if (!tx) return null;
  const sign = tx.type === "adjustment" && tx.quantity < 0 ? -1 : 1;

  const save = async (voiding: boolean) => {
    setSaving(true);
    try {
      await addTransaction({
        productId: tx.productId,
        printing: tx.printing,
        condition: tx.condition,
        grade: tx.grade,
        type: "correction",
        correctsId: tx.id,
        date: voiding ? tx.date : date,
        quantity: voiding ? 0 : sign * qty,
        unitPrice: voiding ? 0 : (parseMoney(price) ?? 0),
        fees: voiding ? 0 : (parseMoney(fees) ?? 0),
        shipping: voiding ? 0 : (parseMoney(shipping) ?? 0),
        tax: voiding ? 0 : (parseMoney(tax) ?? 0),
        notes: reason.trim() || (voiding ? "Deleted" : "Edited"),
      });
      toast.success(voiding ? "Entry deleted" : "Entry updated");
      onOpenChange(false);
    } catch (err) {
      toast.error("Couldn't save correction", { description: err instanceof Error ? err.message : undefined });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <FormShell
          title="Edit entry"
          description="Your totals update right away. The original is kept behind the scenes."
          onSubmit={(e) => {
            e.preventDefault();
            void save(false);
          }}
          footer={
            <div className="flex gap-2">
              <Button type="button" variant="danger" size="lg" className="flex-1" disabled={saving} onClick={() => void save(true)}>
                Delete
              </Button>
              <Button type="submit" variant="primary" size="lg" className="flex-[2]" disabled={saving || qty < 1 || parseMoney(price) === null}>
                {saving && <Loader2 className="animate-spin" />}
                Save changes
              </Button>
            </div>
          }
        >
          <div className="grid grid-cols-2 gap-3">
            <Field label="Quantity">
              <Stepper value={qty} onChange={setQty} label="Corrected quantity" />
            </Field>
            <Field label="Date" htmlFor="cor-date">
              <Input id="cor-date" type="date" value={date} max={today} onChange={(e) => setDate(e.target.value)} />
            </Field>
          </div>
          <Field label={tx.type === "sale" ? "Sale price per unit" : "Price per unit"} htmlFor="cor-price">
            <MoneyInput id="cor-price" value={price} onChange={setPrice} />
          </Field>
          <div className="grid grid-cols-3 gap-3">
            <Field label="Fees" htmlFor="cor-fees">
              <MoneyInput id="cor-fees" value={fees} onChange={setFees} />
            </Field>
            <Field label="Shipping" htmlFor="cor-ship">
              <MoneyInput id="cor-ship" value={shipping} onChange={setShipping} />
            </Field>
            <Field label="Tax" htmlFor="cor-tax">
              <MoneyInput id="cor-tax" value={tax} onChange={setTax} />
            </Field>
          </div>
          <Field label="Reason" hint="Optional" htmlFor="cor-reason">
            <Textarea id="cor-reason" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="What was wrong?" />
          </Field>
        </FormShell>
      </DialogContent>
    </Dialog>
  );
}

export function ManualValueDialog({ holding, open, onOpenChange }: { holding: HoldingView; open: boolean; onOpenChange: (o: boolean) => void }) {
  const { setManualValue } = useStore();
  const [value, setValue] = useState("");
  useEffect(() => {
    if (open) setValue(holding.price !== null ? holding.price.toFixed(2) : "");
  }, [open, holding.price]);
  const v = parseMoney(value);
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <FormShell
          title="Update valuation"
          description={`Per-unit value for ${holding.identity.grade?.company} ${holding.identity.grade?.grade}. Recorded with today's date.`}
          onSubmit={async (e) => {
            e.preventDefault();
            if (v === null) return;
            await setManualValue(holding.identity, v);
            toast.success("Valuation updated");
            onOpenChange(false);
          }}
          footer={
            <Button type="submit" variant="primary" size="lg" className="w-full" disabled={v === null}>
              Save valuation
            </Button>
          }
        >
          <Field label="Value per unit" htmlFor="manual-value">
            <MoneyInput id="manual-value" value={value} onChange={setValue} autoFocus />
          </Field>
        </FormShell>
      </DialogContent>
    </Dialog>
  );
}

/**
 * Deleting records a void correction rather than erasing the row, so totals
 * update immediately while the audit trail survives behind "Show deleted".
 */
export function DeleteTransactionDialog({ tx, open, onOpenChange }: { tx: Transaction | null; open: boolean; onOpenChange: (o: boolean) => void }) {
  const { addTransaction, data } = useStore();
  const [saving, setSaving] = useState(false);
  if (!tx) return null;
  const name = data.products[tx.productId]?.name ?? "this item";
  const label = tx.type === "sale" ? "sale" : tx.type === "adjustment" ? "adjustment" : "purchase";

  const confirm = async () => {
    setSaving(true);
    try {
      await addTransaction({
        productId: tx.productId,
        printing: tx.printing,
        condition: tx.condition,
        grade: tx.grade,
        type: "correction",
        correctsId: tx.id,
        date: tx.date,
        quantity: 0,
        unitPrice: 0,
        fees: 0,
        shipping: 0,
        tax: 0,
        notes: "Deleted",
      });
      toast.success(`Deleted ${label}`);
      onOpenChange(false);
    } catch (err) {
      toast.error("Couldn't delete", { description: err instanceof Error ? err.message : undefined });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Delete this {label}?</DialogTitle>
          <DialogDescription>
            {Math.abs(tx.quantity)} × {name} on {formatDate(tx.date)}. It will be removed from your collection, totals and history.
          </DialogDescription>
        </DialogHeader>
        <div className="flex gap-2 px-6 pb-6 pt-4">
          <Button variant="secondary" size="lg" className="flex-1" onClick={() => onOpenChange(false)} disabled={saving}>
            Cancel
          </Button>
          <Button variant="danger" size="lg" className="flex-1" onClick={() => void confirm()} disabled={saving}>
            {saving && <Loader2 className="animate-spin" />}
            Delete
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

/** Edit / Delete menu for a history row. */
export function TransactionActions({ tx }: { tx: Transaction }) {
  const [dialog, setDialog] = useState<"edit" | "delete" | null>(null);
  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" size="icon-sm" aria-label="Entry actions">
            <MoreHorizontal />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem onSelect={() => setDialog("edit")}>
            <Pencil /> Edit
          </DropdownMenuItem>
          <DropdownMenuItem onSelect={() => setDialog("delete")} className="text-down">
            <Trash2 className="!text-down" /> Delete
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      <CorrectionDialog tx={tx} open={dialog === "edit"} onOpenChange={(o) => !o && setDialog(null)} />
      <DeleteTransactionDialog tx={tx} open={dialog === "delete"} onOpenChange={(o) => !o && setDialog(null)} />
    </>
  );
}

/**
 * Split a transaction list into what to show by default and what to tuck
 * away: deleted entries and the correction records that edited or deleted them.
 */
export function partitionHistory(all: Transaction[]) {
  const effective = new Map(effectiveTransactions(all).map((t) => [t.id, t]));
  const isHidden = (t: Transaction) => t.type === "correction" || !effective.has(t.id);
  return { effective, visible: all.filter((t) => !isHidden(t)), hidden: all.filter(isHidden) };
}
