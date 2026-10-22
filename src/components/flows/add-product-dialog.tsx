"use client";

import { ChevronDown, ChevronLeft, Loader2 } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { Input, Textarea } from "@/components/ui/input";
import { Segmented } from "@/components/ui/segmented";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { ProductImage } from "@/components/product/product-image";
import { categoryOf } from "@/lib/catalog";
import { money } from "@/lib/format";
import type { SearchHit } from "@/lib/pricing/types";
import { useStore, type ImportedProduct } from "@/lib/store/collection-store";
import { CONDITIONS, priceKey, type Condition } from "@/lib/types";
import { cn } from "@/lib/utils";
import { Field, MoneyInput, Stepper, SummaryRow, parseMoney } from "./fields";
import { ProductSearch } from "./product-search";

const GRADERS = ["PSA", "BGS", "CGC", "SGC", "TAG"];

export function AddProductDialog() {
  const { addTarget, closeAdd, data } = useStore();
  const [hit, setHit] = useState<SearchHit | null>(null);

  // Opening with a known product skips straight to the form.
  useEffect(() => {
    if (!addTarget.open) {
      const t = setTimeout(() => setHit(null), 250);
      return () => clearTimeout(t);
    }
    if (addTarget.productId) {
      const product = data.products[addTarget.productId];
      if (product) {
        const printing = product.printings?.[0] ?? null;
        setHit({ product, printing, market: data.prices[priceKey(product.id, printing)]?.market ?? null, priceUpdatedAt: null });
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [addTarget.open, addTarget.productId]);

  const watch = Boolean(addTarget.watch);

  return (
    <Dialog open={addTarget.open} onOpenChange={(o) => !o && closeAdd()}>
      <DialogContent className="h-[88dvh] sm:h-[640px] sm:max-w-[560px]" aria-describedby={undefined}>
        {!hit ? (
          <>
            <div className="px-6 pt-6">
              <DialogTitle>{watch ? "Add to Watchlist" : "Add to Collection"}</DialogTitle>
            </div>
            <ProductSearch onSelect={setHit} />
          </>
        ) : watch ? (
          <WatchForm hit={hit} onBack={addTarget.productId ? undefined : () => setHit(null)} onDone={closeAdd} />
        ) : (
          <PurchaseForm hit={hit} fromWatchId={addTarget.fromWatchId} onBack={addTarget.productId ? undefined : () => setHit(null)} onDone={closeAdd} />
        )}
      </DialogContent>
    </Dialog>
  );
}

function useImported(hit: SearchHit) {
  const { importProduct } = useStore();
  const [imported, setImported] = useState<ImportedProduct | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let cancelled = false;
    setImported(null);
    setError(null);
    importProduct(hit.product.id, hit.printing)
      .then((r) => !cancelled && setImported(r))
      .catch((e: Error) => !cancelled && setError(e.message));
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hit.product.id]);
  return { imported, error };
}

function ProductHeader({ hit, imported, printing, onBack }: { hit: SearchHit; imported: ImportedProduct | null; printing: string | null; onBack?: () => void }) {
  const product = imported?.product ?? hit.product;
  const price = imported?.prices.find((p) => p.printing === printing) ?? null;
  const market = price ? price.market : hit.market;
  return (
    <div className="flex items-center gap-4 border-b border-border px-6 pb-5 pt-6">
      {onBack && (
        <button onClick={onBack} aria-label="Back to search" className="-ml-2 rounded-full p-1.5 text-muted hover:bg-surface-2 hover:text-foreground">
          <ChevronLeft className="size-5" />
        </button>
      )}
      <ProductImage product={product} size="sm" className="size-16 shrink-0 rounded-xl" />
      <div className="min-w-0 flex-1 pr-6">
        <DialogTitle className="truncate text-[17px]">{product.name}</DialogTitle>
        <DialogDescription className="mt-0.5 truncate">
          {[product.setName, categoryOf(product)].filter(Boolean).join(" · ")}
        </DialogDescription>
        <p className="tabular mt-1 text-[13px]">
          {market === null ? <span className="text-subtle">No market price</span> : <span className="font-medium">{money(market)}</span>}
          <span className="text-subtle"> market</span>
          {product.source === "sample" && (
            <Badge variant="sample" className="ml-2">
              Sample
            </Badge>
          )}
        </p>
      </div>
    </div>
  );
}

function PrintingSelect({ options, value, onChange }: { options: string[]; value: string | null; onChange: (v: string) => void }) {
  if (options.length <= 1) return null;
  return (
    <Field label="Printing">
      <Select value={value ?? undefined} onValueChange={onChange}>
        <SelectTrigger aria-label="Printing">
          <SelectValue placeholder="Choose printing" />
        </SelectTrigger>
        <SelectContent>
          {options.map((p) => (
            <SelectItem key={p} value={p}>
              {p}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </Field>
  );
}

function PurchaseForm({ hit, fromWatchId, onBack, onDone }: { hit: SearchHit; fromWatchId?: string; onBack?: () => void; onDone: () => void }) {
  const { addTransaction, setManualValue, removeWatch, today } = useStore();
  const router = useRouter();
  const { imported, error } = useImported(hit);
  const product = imported?.product ?? hit.product;
  const sealed = product.kind === "sealed";

  const printings = useMemo(() => {
    const fromPrices = imported?.prices.map((p) => p.printing).filter((p): p is string => Boolean(p)) ?? [];
    return fromPrices.length ? fromPrices : hit.printing ? [hit.printing] : [];
  }, [imported, hit.printing]);

  const [printing, setPrinting] = useState<string | null>(hit.printing);
  const [qty, setQty] = useState(1);
  const [priceMode, setPriceMode] = useState<"unit" | "lot">("unit");
  const [price, setPrice] = useState(hit.market !== null ? hit.market.toFixed(2) : "");
  const [date, setDate] = useState(today);
  const [condition, setCondition] = useState<Condition>(sealed ? "Sealed" : "Near Mint");
  const [graded, setGraded] = useState(false);
  const [grader, setGrader] = useState("PSA");
  const [grade, setGrade] = useState("10");
  const [gradedValue, setGradedValue] = useState("");
  const [showExtras, setShowExtras] = useState(false);
  const [shipping, setShipping] = useState("");
  const [fees, setFees] = useState("");
  const [tax, setTax] = useState("");
  const [source, setSource] = useState("");
  const [notes, setNotes] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!printing && printings.length) setPrinting(printings[0]);
  }, [printings, printing]);

  const entered = parseMoney(price);
  const unitPrice = entered === null ? null : priceMode === "unit" ? entered : qty > 0 ? entered / qty : null;
  const extras = (parseMoney(shipping) ?? 0) + (parseMoney(fees) ?? 0) + (parseMoney(tax) ?? 0);
  const subtotal = unitPrice === null ? null : unitPrice * qty;
  const total = subtotal === null ? null : subtotal + extras;
  const valid = qty >= 1 && unitPrice !== null && date <= today && (!graded || grade.trim() !== "");

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!valid || unitPrice === null) return;
    setSaving(true);
    try {
      const identity = {
        productId: product.id,
        printing,
        condition: graded ? ("Near Mint" as Condition) : condition,
        grade: graded ? { company: grader, grade: grade.trim() } : null,
      };
      await addTransaction({
        ...identity,
        type: "purchase",
        date,
        quantity: qty,
        unitPrice,
        shipping: parseMoney(shipping) ?? 0,
        fees: parseMoney(fees) ?? 0,
        tax: parseMoney(tax) ?? 0,
        source: source.trim() || null,
        notes: notes.trim() || null,
      });
      const gv = parseMoney(gradedValue);
      if (graded && gv !== null) await setManualValue(identity, gv);
      if (fromWatchId) await removeWatch(fromWatchId);
      toast.success(`Added ${qty} × ${product.name}`, {
        description: `Cost basis ${money(total)}`,
        action: { label: "View", onClick: () => router.push(`/product/${encodeURIComponent(product.id)}`) },
      });
      onDone();
    } catch (err) {
      toast.error("Couldn't save purchase", { description: err instanceof Error ? err.message : undefined });
    } finally {
      setSaving(false);
    }
  };

  return (
    <form onSubmit={submit} className="flex min-h-0 flex-1 flex-col">
      <ProductHeader hit={hit} imported={imported} printing={printing} onBack={onBack} />
      <div className="flex-1 space-y-5 overflow-y-auto px-6 py-5">
        {error && <p className="rounded-xl bg-down-soft px-3 py-2 text-[13px] text-down">{error}</p>}
        <div className="grid grid-cols-2 gap-3">
          <Field label="Quantity">
            <Stepper value={qty} onChange={setQty} label="Quantity" />
          </Field>
          <Field label="Purchase date" htmlFor="purchase-date">
            <Input id="purchase-date" type="date" value={date} max={today} onChange={(e) => setDate(e.target.value)} className="tabular" />
          </Field>
        </div>

        <Field
          label={priceMode === "unit" ? "Price per unit" : "Total lot price"}
          htmlFor="purchase-price"
          hint={
            <Segmented
              ariaLabel="Price entry"
              size="sm"
              value={priceMode}
              onChange={(m) => {
                const v = parseMoney(price);
                if (v !== null && qty > 0) setPrice((m === "lot" ? v * qty : v / qty).toFixed(2));
                setPriceMode(m);
              }}
              options={[
                { value: "unit", label: "Per unit" },
                { value: "lot", label: "Lot total" },
              ]}
            />
          }
        >
          <MoneyInput id="purchase-price" value={price} onChange={setPrice} />
          {priceMode === "lot" && unitPrice !== null && qty > 1 && <p className="tabular text-[12px] text-subtle">{money(unitPrice)} per unit</p>}
        </Field>

        <div className="grid grid-cols-2 gap-3">
          <PrintingSelect options={printings} value={printing} onChange={setPrinting} />
          {!graded && (
            <Field label="Condition" className={printings.length <= 1 ? "col-span-2" : undefined}>
              <Select value={condition} onValueChange={(v) => setCondition(v as Condition)}>
                <SelectTrigger aria-label="Condition">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {CONDITIONS.filter((c) => (sealed ? c === "Sealed" || c === "Damaged" : c !== "Sealed")).map((c) => (
                    <SelectItem key={c} value={c}>
                      {c}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
          )}
        </div>

        {!sealed && (
          <div className="rounded-2xl border border-border p-4">
            <label className="flex items-center justify-between gap-3">
              <span>
                <span className="block text-[14px] font-medium">Graded card</span>
                <span className="block text-[12px] text-muted">Valued manually — graded prices aren&apos;t provided by the pricing source.</span>
              </span>
              <Switch checked={graded} onCheckedChange={setGraded} aria-label="Graded card" />
            </label>
            {graded && (
              <div className="mt-4 grid grid-cols-3 gap-3">
                <Field label="Grader">
                  <Select value={grader} onValueChange={setGrader}>
                    <SelectTrigger aria-label="Grader">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {GRADERS.map((g) => (
                        <SelectItem key={g} value={g}>
                          {g}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </Field>
                <Field label="Grade" htmlFor="grade">
                  <Input id="grade" value={grade} onChange={(e) => setGrade(e.target.value.slice(0, 6))} inputMode="decimal" />
                </Field>
                <Field label="Value est." htmlFor="graded-value">
                  <MoneyInput id="graded-value" value={gradedValue} onChange={setGradedValue} placeholder="Optional" />
                </Field>
              </div>
            )}
          </div>
        )}

        <div>
          <button type="button" onClick={() => setShowExtras((s) => !s)} className="flex items-center gap-1.5 text-[13px] font-medium text-muted hover:text-foreground" aria-expanded={showExtras}>
            <ChevronDown className={cn("size-4 transition-transform", showExtras && "rotate-180")} />
            Shipping, fees, tax &amp; notes
          </button>
          {showExtras && (
            <div className="mt-4 space-y-4 animate-rise">
              <div className="grid grid-cols-3 gap-3">
                <Field label="Shipping" htmlFor="shipping">
                  <MoneyInput id="shipping" value={shipping} onChange={setShipping} />
                </Field>
                <Field label="Fees" htmlFor="fees">
                  <MoneyInput id="fees" value={fees} onChange={setFees} />
                </Field>
                <Field label="Tax" htmlFor="tax">
                  <MoneyInput id="tax" value={tax} onChange={setTax} />
                </Field>
              </div>
              <Field label="Purchased from" htmlFor="source">
                <Input id="source" value={source} onChange={(e) => setSource(e.target.value)} placeholder="e.g. Local game store, eBay" />
              </Field>
              <Field label="Notes" htmlFor="notes">
                <Textarea id="notes" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Optional" />
              </Field>
            </div>
          )}
        </div>
      </div>

      <div className="border-t border-border bg-surface px-6 pb-6 pt-4">
        <div className="space-y-1.5">
          {extras > 0 && <SummaryRow label="Subtotal" value={money(subtotal)} />}
          {extras > 0 && <SummaryRow label="Shipping, fees & tax" value={money(extras)} />}
          <SummaryRow strong label="Total cost basis" value={money(total)} />
        </div>
        <Button type="submit" variant="primary" size="lg" className="mt-4 w-full" disabled={!valid || saving}>
          {saving && <Loader2 className="animate-spin" />}
          Add to Collection
        </Button>
      </div>
    </form>
  );
}

function WatchForm({ hit, onBack, onDone }: { hit: SearchHit; onBack?: () => void; onDone: () => void }) {
  const { addWatch, data } = useStore();
  const { imported, error } = useImported(hit);
  const printings = imported?.prices.map((p) => p.printing).filter((p): p is string => Boolean(p)) ?? (hit.printing ? [hit.printing] : []);
  const [printing, setPrinting] = useState<string | null>(hit.printing);
  const [target, setTarget] = useState("");
  const [saving, setSaving] = useState(false);
  const exists = data.watchlist.some((w) => w.productId === hit.product.id && w.printing === printing);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    try {
      await addWatch(hit.product.id, printing, parseMoney(target));
      toast.success(`Watching ${hit.product.name}`);
      onDone();
    } catch (err) {
      toast.error("Couldn't add to watchlist", { description: err instanceof Error ? err.message : undefined });
    } finally {
      setSaving(false);
    }
  };

  return (
    <form onSubmit={submit} className="flex min-h-0 flex-1 flex-col">
      <ProductHeader hit={hit} imported={imported} printing={printing} onBack={onBack} />
      <div className="flex-1 space-y-5 overflow-y-auto px-6 py-5">
        {error && <p className="rounded-xl bg-down-soft px-3 py-2 text-[13px] text-down">{error}</p>}
        <PrintingSelect options={printings} value={printing} onChange={setPrinting} />
        <Field label="Target purchase price" hint="Optional" htmlFor="target">
          <MoneyInput id="target" value={target} onChange={setTarget} autoFocus />
        </Field>
        <p className="text-[13px] text-muted">Watchlist items are tracked separately and never affect your portfolio value.</p>
      </div>
      <div className="border-t border-border px-6 pb-6 pt-4">
        <Button type="submit" variant="primary" size="lg" className="w-full" disabled={saving || exists}>
          {saving && <Loader2 className="animate-spin" />}
          {exists ? "Already on your watchlist" : "Add to Watchlist"}
        </Button>
      </div>
    </form>
  );
}
