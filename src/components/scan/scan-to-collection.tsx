"use client";

import { Loader2 } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { parseMoney } from "@/components/flows/fields";
import { Button } from "@/components/ui/button";
import { Segmented } from "@/components/ui/segmented";
import { money } from "@/lib/format";
import { useStore } from "@/lib/store/collection-store";
import type { Condition } from "@/lib/types";
import { scanValue } from "@/lib/scan-types";
import { ScanSheet, type ScanPick } from "./scan-sheet";

type Paid = "market" | "pulled";

/**
 * Scan a stack of cards into the collection: every match lands in the tray
 * with what you paid (market price by default, or nothing for pack pulls,
 * editable per card), then one tap adds them all as today's purchases.
 */
export function ScanToCollection({ open, onOpenChange, onDone }: { open: boolean; onOpenChange: (o: boolean) => void; onDone?: () => void }) {
  const { importProduct, addTransaction, today, mode } = useStore();
  const [paidMode, setPaidMode] = useState<Paid>("market");
  const [paid, setPaid] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState(false);

  const costOf = (pick: ScanPick) => {
    const typed = parseMoney(paid[pick.entryId] ?? "");
    if (typed !== null) return typed;
    return paidMode === "pulled" ? 0 : (scanValue(pick.candidate, pick.read) ?? 0);
  };

  const addAll = async (picks: ScanPick[]) => {
    setSaving(true);
    let added = 0;
    try {
      for (const pick of picks) {
        const c = pick.candidate;
        const imported = await importProduct(c.product.id, c.printing, c.product.kind);
        const slab = pick.read?.kind === "slab" ? (pick.read.grade ?? null) : null;
        await addTransaction({
          productId: imported.product.id,
          printing: c.printing,
          condition: (imported.product.kind === "sealed" ? "Sealed" : "Near Mint") as Condition,
          grade: slab,
          type: "purchase",
          date: today,
          quantity: 1,
          unitPrice: costOf(pick),
          fees: 0,
          shipping: 0,
          tax: 0,
          source: "Scanned",
          notes: null,
        });
        added++;
      }
      toast.success(`Added ${added} to your collection`);
      setPaid({});
      onOpenChange(false);
      onDone?.();
    } catch (err) {
      toast.error(added ? `Added ${added}, then stopped` : "Couldn't add those", { description: err instanceof Error ? err.message : undefined });
    } finally {
      setSaving(false);
    }
  };

  return (
    <ScanSheet
      open={open}
      onOpenChange={onOpenChange}
      title="Scan to collection"
      description={mode === "demo" ? "Demo mode can't add scanned cards. Switch to your collection to keep them." : "Scan each card, check what you paid, then add them all."}
      onPick={() => ({ ok: true })}
      disabled={mode === "demo"}
      extra={(pick) => (
        <div className="mt-2 flex items-center gap-2 pl-14">
          <span className="text-[12px] text-muted">Paid</span>
          <span className="relative">
            <span className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-[13px] text-subtle">$</span>
            <input
              inputMode="decimal"
              aria-label={`What you paid for ${pick.candidate.product.name}`}
              value={paid[pick.entryId] ?? ""}
              placeholder={costOf(pick).toFixed(2)}
              onChange={(e) => setPaid((p) => ({ ...p, [pick.entryId]: e.target.value.replace(/[^0-9.]/g, "") }))}
              className="tabular h-8 w-28 rounded-full bg-surface-3 pl-6 pr-2 text-[13px] outline-none placeholder:text-foreground/70"
            />
          </span>
          {pick.read?.kind === "slab" && pick.read.grade && <span className="text-[12px] text-muted">{`${pick.read.grade.company} ${pick.read.grade.grade}`}</span>}
        </div>
      )}
      footer={(picks) => (
        <div className="space-y-3">
          <div className="flex items-center justify-between gap-3">
            <span className="text-[13px] text-muted">If you don&apos;t enter one, you paid</span>
            <Segmented
              ariaLabel="Default paid"
              size="sm"
              value={paidMode}
              onChange={setPaidMode}
              options={[
                { value: "market", label: "Market" },
                { value: "pulled", label: "$0 (pulled)" },
              ]}
            />
          </div>
          <Button variant="lime" size="lg" className="w-full" disabled={saving || mode === "demo"} onClick={() => void addAll(picks)}>
            {saving && <Loader2 className="animate-spin" />}
            Add {picks.length} to collection · {money(picks.reduce((s, p) => s + costOf(p), 0))}
          </Button>
        </div>
      )}
    />
  );
}
