"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import { Loader2, Pencil, Trash2, X } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { CorrectionDialog } from "@/components/flows/transaction-dialogs";
import { undoToast } from "@/components/ui/undo-toast";
import { effectiveTransactions } from "@/lib/finance/ledger";
import { restoreEntry, voidEntry } from "@/lib/holding-actions";
import { useStore } from "@/lib/store/collection-store";
import type { Transaction } from "@/lib/types";
import { cn } from "@/lib/utils";

const sheet = "fixed z-50 flex flex-col gap-2 bg-[#161618] p-4 pb-[calc(1rem+env(safe-area-inset-bottom))] shadow-2xl shadow-black/50 outline-none data-[state=open]:animate-rise inset-x-0 bottom-0 rounded-t-[1.75rem] sm:inset-x-auto sm:bottom-auto sm:left-1/2 sm:top-[18vh] sm:w-[360px] sm:-translate-x-1/2 sm:rounded-[1.5rem] sm:pb-4";
const glassButton = "glass flex h-12 w-full items-center justify-center gap-2 rounded-2xl text-[15px] font-medium transition-colors hover:bg-foreground/10";
const dangerButton =
  "flex h-12 w-full items-center justify-center gap-2 rounded-2xl bg-[color-mix(in_srgb,var(--plan-pink)_14%,transparent)] text-[15px] font-semibold text-[var(--plan-pink)] ring-1 ring-inset ring-[color-mix(in_srgb,var(--plan-pink)_30%,transparent)] disabled:opacity-60";

/**
 * A log entry's ⋯ (the app's `ActionsSheet`): a small dark sheet with Edit and Delete as two
 * full-width buttons. Edit opens the correction form; Delete asks first, then records a void
 * correction (the original stays in the record) with Undo.
 */
export function EntryActions({
  tx,
  title,
  noun = "entry",
  deleteNote,
  onClose,
}: {
  tx: Transaction | null;
  title: string;
  /** "sale" → Edit sale / Delete sale. */
  noun?: string;
  deleteNote: string;
  onClose: () => void;
}) {
  const { data, addTransaction } = useStore();
  const [step, setStep] = useState<"menu" | "confirm" | "edit">("menu");
  const [last, setLast] = useState(tx);
  const [saving, setSaving] = useState(false);
  if (tx && tx !== last) {
    setLast(tx);
    setStep("menu");
  }
  const t = tx ?? last;
  const label = noun === "entry" ? "" : ` ${noun}`;

  const close = () => {
    onClose();
  };

  const remove = async () => {
    if (!t) return;
    setSaving(true);
    const before = effectiveTransactions(data.transactions.filter((x) => x.productId === t.productId)).find((x) => x.id === t.id) ?? null;
    try {
      await addTransaction(voidEntry(t));
      close();
      if (before) undoToast(`Deleted ${noun}`, () => addTransaction(restoreEntry(before)));
      else toast.success(`Deleted ${noun}`);
    } catch (err) {
      toast.error("Couldn't delete", { description: err instanceof Error ? err.message : undefined });
    } finally {
      setSaving(false);
    }
  };

  return (
    <>
      <DialogPrimitive.Root open={tx !== null && step !== "edit"} onOpenChange={(o) => !o && close()}>
        <DialogPrimitive.Portal>
          <DialogPrimitive.Overlay className="fixed inset-0 z-50 bg-black/50 data-[state=open]:animate-fade-in" />
          <DialogPrimitive.Content aria-describedby={undefined} className={sheet}>
            <div className="mb-1 flex items-center gap-3">
              <DialogPrimitive.Title className="min-w-0 flex-1 truncate text-[15px] font-semibold">{step === "confirm" ? `Delete this ${noun}?` : title}</DialogPrimitive.Title>
              <DialogPrimitive.Close aria-label="Close" className="glass flex size-8 shrink-0 items-center justify-center rounded-full">
                <X className="size-4" />
              </DialogPrimitive.Close>
            </div>
            {step === "menu" ? (
              <>
                <button type="button" className={glassButton} onClick={() => setStep("edit")}>
                  <Pencil className="size-4 text-muted" /> Edit{label}
                </button>
                <button type="button" className={cn(dangerButton, "mt-1")} onClick={() => setStep("confirm")}>
                  <Trash2 className="size-4" /> Delete{label}
                </button>
              </>
            ) : (
              <>
                <p className="mb-2 text-balance text-[14px] text-muted">{deleteNote}</p>
                <div className="flex gap-2">
                  <button type="button" className={glassButton} onClick={() => setStep("menu")} disabled={saving}>
                    Cancel
                  </button>
                  <button type="button" className={dangerButton} onClick={() => void remove()} disabled={saving}>
                    {saving && <Loader2 className="size-4 animate-spin" />}
                    Delete
                  </button>
                </div>
              </>
            )}
          </DialogPrimitive.Content>
        </DialogPrimitive.Portal>
      </DialogPrimitive.Root>
      <CorrectionDialog tx={step === "edit" ? t : null} open={tx !== null && step === "edit"} onOpenChange={(o) => !o && close()} />
    </>
  );
}
