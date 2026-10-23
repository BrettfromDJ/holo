"use client";

import { Loader2 } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import { Delta } from "@/components/product/delta";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Segmented } from "@/components/ui/segmented";
import type { HoldingView } from "@/lib/finance/portfolio";
import { PLATFORMS, estimateSale, type SellPlatform } from "@/lib/finance/sell";
import { money, signedMoney } from "@/lib/format";
import { useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";
import { Field, MoneyInput, Stepper, parseMoney } from "./fields";

/**
 * "What if I sell?" — estimate what you'd actually keep after marketplace
 * fees and shipping, the profit against your FIFO cost basis, and the
 * break-even price. Optionally records the sale with those exact numbers.
 */
export function SellCalculatorDialog({ holding, open, onOpenChange }: { holding: HoldingView; open: boolean; onOpenChange: (o: boolean) => void }) {
  const { addTransaction, today } = useStore();
  const [platform, setPlatform] = useState<SellPlatform>("ebay");
  const [qty, setQty] = useState(1);
  const [price, setPrice] = useState("");
  const [percent, setPercent] = useState("");
  const [fixed, setFixed] = useState("");
  const [shipCharged, setShipCharged] = useState("");
  const [shipCost, setShipCost] = useState("");
  const [editFees, setEditFees] = useState(false);
  const [saving, setSaving] = useState(false);

  const applyPlatform = (id: SellPlatform) => {
    const p = PLATFORMS.find((x) => x.id === id)!;
    setPlatform(id);
    setPercent(String(p.fees.percent));
    setFixed(p.fees.fixed.toFixed(2));
    setEditFees(id === "custom");
    if (id === "local") {
      setShipCharged("");
      setShipCost("");
    }
  };

  useEffect(() => {
    if (!open) return;
    setQty(1);
    setPrice(holding.price !== null ? holding.price.toFixed(2) : "");
    setShipCharged("");
    setShipCost("");
    applyPlatform("ebay");
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  const unitPrice = parseMoney(price);
  const estimate = useMemo(
    () =>
      estimateSale(holding.lots, {
        quantity: qty,
        unitPrice: unitPrice ?? 0,
        fees: { percent: Number(percent) || 0, fixed: parseMoney(fixed) ?? 0 },
        shippingCharged: parseMoney(shipCharged) ?? 0,
        shippingCost: parseMoney(shipCost) ?? 0,
      }),
    [holding.lots, qty, unitPrice, percent, fixed, shipCharged, shipCost],
  );
  const platformMeta = PLATFORMS.find((p) => p.id === platform)!;
  const ready = unitPrice !== null && qty >= 1;
  const tone = estimate.profit > 0.005 ? "up" : estimate.profit < -0.005 ? "down" : "flat";

  const record = async () => {
    if (!ready || unitPrice === null) return;
    setSaving(true);
    try {
      // Store so that recorded net proceeds equal the estimate exactly:
      // shipping charged to the buyer is income, shipping paid is a cost.
      const shipNet = (parseMoney(shipCharged) ?? 0) - (parseMoney(shipCost) ?? 0);
      await addTransaction({
        ...holding.identity,
        type: "sale",
        date: today,
        quantity: estimate.quantity,
        unitPrice: shipNet > 0 ? unitPrice + shipNet / estimate.quantity : unitPrice,
        fees: Math.round(estimate.platformFees * 100) / 100,
        shipping: shipNet < 0 ? Math.round(-shipNet * 100) / 100 : 0,
        tax: 0,
        source: platformMeta.label,
        notes: `Sold via ${platformMeta.label}`,
      });
      toast.success(`Recorded sale of ${estimate.quantity} × ${holding.product?.name ?? "item"}`, { description: `Realized ${signedMoney(estimate.profit)}` });
      onOpenChange(false);
    } catch (err) {
      toast.error("Couldn't record sale", { description: err instanceof Error ? err.message : undefined });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[520px]">
        <DialogHeader>
          <DialogTitle>What if I sell?</DialogTitle>
          <DialogDescription>
            {holding.product?.name ?? "Item"} · {holding.quantity} owned · market {money(holding.price)}
          </DialogDescription>
        </DialogHeader>

        <div className="flex-1 space-y-4 overflow-y-auto px-6 py-4">
          <Segmented ariaLabel="Where you'd sell" value={platform} onChange={applyPlatform} options={PLATFORMS.map((p) => ({ value: p.id, label: p.label }))} />

          <div className="grid grid-cols-2 gap-3">
            <Field label="Quantity" hint={`of ${holding.quantity}`}>
              <Stepper value={qty} onChange={setQty} max={holding.quantity} label="Quantity to sell" />
            </Field>
            <Field label="Sale price each" htmlFor="sell-price">
              <MoneyInput id="sell-price" value={price} onChange={setPrice} />
            </Field>
          </div>

          {platform !== "local" && (
            <div className="grid grid-cols-2 gap-3">
              <Field label="Shipping buyer pays" hint="order total" htmlFor="ship-charged">
                <MoneyInput id="ship-charged" value={shipCharged} onChange={setShipCharged} />
              </Field>
              <Field label="Your shipping cost" hint="order total" htmlFor="ship-cost">
                <MoneyInput id="ship-cost" value={shipCost} onChange={setShipCost} />
              </Field>
            </div>
          )}

          {platform !== "local" &&
            (editFees ? (
              <div className="grid grid-cols-2 gap-3">
                <Field label="Fee %" htmlFor="fee-pct">
                  <div className="relative">
                    <input
                      id="fee-pct"
                      inputMode="decimal"
                      value={percent}
                      onChange={(e) => setPercent(e.target.value.replace(/[^0-9.]/g, ""))}
                      className="tabular h-11 w-full rounded-xl border border-border bg-surface-2 pl-3.5 pr-8 text-[15px] outline-none focus:border-border-strong focus:bg-surface-3"
                    />
                    <span className="pointer-events-none absolute right-3.5 top-1/2 -translate-y-1/2 text-subtle">%</span>
                  </div>
                </Field>
                <Field label="Per-order fee" htmlFor="fee-fixed">
                  <MoneyInput id="fee-fixed" value={fixed} onChange={setFixed} />
                </Field>
              </div>
            ) : (
              <p className="text-[12px] text-subtle">
                Fees: {percent}% + {money(parseMoney(fixed) ?? 0)} per order · {platformMeta.note}.{" "}
                <button onClick={() => setEditFees(true)} className="font-medium text-muted underline-offset-2 hover:text-foreground hover:underline">
                  Edit
                </button>
              </p>
            ))}

          <div className="rounded-2xl bg-surface-2 p-4">
            <p className="text-[12px] font-medium text-muted">You&apos;d make</p>
            <p className={cn("tabular mt-1 text-[30px] font-semibold leading-none tracking-tight", !ready && "text-subtle")}>
              {ready ? <Delta value={estimate.profit} ratio={estimate.profitPct} /> : "—"}
            </p>
            <dl className="tabular mt-4 space-y-1.5 text-[13px]">
              <Line label={`Sale (${estimate.quantity} × ${money(unitPrice ?? 0)})`} value={money(estimate.gross)} />
              {(parseMoney(shipCharged) ?? 0) > 0 && <Line label="Shipping buyer pays" value={`+${money(parseMoney(shipCharged))}`} />}
              {estimate.platformFees > 0 && <Line label={platform === "custom" ? "Fees" : `${platformMeta.label} fees`} value={`−${money(estimate.platformFees)}`} />}
              {(parseMoney(shipCost) ?? 0) > 0 && <Line label="Your shipping cost" value={`−${money(parseMoney(shipCost))}`} />}
              <Line label="You receive" value={money(estimate.net)} strong />
              <Line label="Cost basis (oldest units first)" value={`−${money(estimate.costBasis)}`} />
              <div className="flex items-center justify-between border-t border-border pt-1.5 font-semibold">
                <dt>Profit</dt>
                <dd className={tone === "up" ? "text-up" : tone === "down" ? "text-down" : ""}>{ready ? signedMoney(estimate.profit) : "—"}</dd>
              </div>
            </dl>
            {estimate.breakEvenUnitPrice !== null && (
              <p className="mt-3 text-[12px] text-muted">
                Break-even: <span className="tabular font-medium text-foreground">{money(estimate.breakEvenUnitPrice)}</span> each
                {holding.price !== null && <span> · market is {money(holding.price)}</span>}
              </p>
            )}
          </div>
        </div>

        <div className="flex gap-2 border-t border-border px-6 pb-6 pt-4">
          <Button variant="secondary" size="lg" className="flex-1" onClick={() => onOpenChange(false)}>
            Close
          </Button>
          <Button variant="primary" size="lg" className="flex-1" disabled={!ready || saving} onClick={() => void record()}>
            {saving && <Loader2 className="animate-spin" />}
            Record this sale
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

function Line({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
  return (
    <div className={cn("flex items-center justify-between gap-3", strong ? "font-medium text-foreground" : "text-muted")}>
      <dt className="truncate">{label}</dt>
      <dd>{value}</dd>
    </div>
  );
}
