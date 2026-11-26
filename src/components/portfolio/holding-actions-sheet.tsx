"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import { ArrowLeft, Check, CheckCircle2, ExternalLink, Library, Trash2, Wallet, X } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { cardHref } from "@/components/portfolio/collection-links";
import { undoToast } from "@/components/ui/undo-toast";
import type { HoldingView } from "@/lib/finance/portfolio";
import { liveEntries, restoreEntry, voidEntry } from "@/lib/holding-actions";
import { useStore } from "@/lib/store/collection-store";
import { useShelves } from "@/lib/store/shelves";
import { cn } from "@/lib/utils";

/**
 * A card row's actions (the app's `ActionsSheet` behind a row's ⋯): a small dark sheet of quiet
 * glass rows. Open, Your copy, Select, Add to list (a second page with a round back button) and
 * Delete (pink, with Undo). A bottom sheet on phones, a small centred card on wide screens.
 */
export function HoldingActionsSheet({
  holding,
  onOpenChange,
  onYourCopy,
  onSelect,
}: {
  holding: HoldingView | null;
  onOpenChange: (open: boolean) => void;
  onYourCopy: (h: HoldingView) => void;
  onSelect: (h: HoldingView) => void;
}) {
  const router = useRouter();
  const { data, addTransaction } = useStore();
  const { shelves, toggle } = useShelves();
  const [page, setPage] = useState<"main" | "lists">("main");
  const [last, setLast] = useState(holding);
  if (holding && holding !== last) setLast(holding);
  const h = holding ?? last;
  useEffect(() => {
    if (holding) setPage("main");
  }, [holding]);

  // Actions run after the sheet closes (as in the app).
  const then = (run: () => void) => {
    onOpenChange(false);
    window.setTimeout(run, 180);
  };

  const remove = (target: HoldingView) =>
    then(() => {
      const live = liveEntries(data.transactions, target.key);
      void (async () => {
        try {
          for (const t of live) await addTransaction(voidEntry(t));
          undoToast(`Deleted ${target.product?.name ?? "it"} from your collection`, async () => {
            for (const t of live) await addTransaction(restoreEntry(t));
          });
        } catch (err) {
          toast.error("Couldn't delete", { description: err instanceof Error ? err.message : undefined });
        }
      })();
    });

  const row = "glass flex h-12 w-full items-center gap-3 rounded-2xl px-4 text-left text-[15px] font-medium transition-colors hover:bg-foreground/10";

  return (
    <DialogPrimitive.Root open={holding !== null} onOpenChange={onOpenChange}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="fixed inset-0 z-50 bg-black/50 data-[state=open]:animate-fade-in" />
        <DialogPrimitive.Content
          aria-describedby={undefined}
          className={cn(
            "fixed z-50 flex flex-col gap-2 bg-[#161618] p-4 pb-[calc(1rem+env(safe-area-inset-bottom))] shadow-2xl shadow-black/50 outline-none data-[state=open]:animate-rise",
            "inset-x-0 bottom-0 rounded-t-[1.75rem] sm:inset-x-auto sm:bottom-auto sm:left-1/2 sm:top-[18vh] sm:w-[360px] sm:-translate-x-1/2 sm:rounded-[1.5rem] sm:pb-4",
          )}
        >
          <div className="mb-1 flex items-center gap-3">
            {page === "lists" && (
              <button type="button" onClick={() => setPage("main")} aria-label="Back" className="glass flex size-8 shrink-0 items-center justify-center rounded-full">
                <ArrowLeft className="size-4" />
              </button>
            )}
            <DialogPrimitive.Title className="min-w-0 flex-1 truncate text-[15px] font-semibold">{page === "lists" ? "Add to list" : (h?.product?.name ?? "Card")}</DialogPrimitive.Title>
            <DialogPrimitive.Close aria-label="Close" className="glass flex size-8 shrink-0 items-center justify-center rounded-full">
              <X className="size-4" />
            </DialogPrimitive.Close>
          </div>
          {h && page === "main" && (
            <>
              <button type="button" className={row} onClick={() => then(() => router.push(cardHref(h)))}>
                <ExternalLink className="size-[18px] text-muted" /> Open card
              </button>
              <button type="button" className={row} onClick={() => then(() => onYourCopy(h))}>
                <Wallet className="size-[18px] text-muted" /> Your copy
              </button>
              <button type="button" className={row} onClick={() => then(() => onSelect(h))}>
                <CheckCircle2 className="size-[18px] text-muted" /> Select
              </button>
              {shelves.length > 0 && (
                <button type="button" className={row} onClick={() => setPage("lists")}>
                  <Library className="size-[18px] text-muted" /> Add to list
                </button>
              )}
              <button
                type="button"
                onClick={() => remove(h)}
                className="mt-1 flex h-12 w-full items-center justify-center gap-2 rounded-2xl bg-[color-mix(in_srgb,var(--plan-pink)_14%,transparent)] text-[15px] font-semibold text-[var(--plan-pink)] ring-1 ring-inset ring-[color-mix(in_srgb,var(--plan-pink)_30%,transparent)]"
              >
                <Trash2 className="size-4" /> Delete
              </button>
            </>
          )}
          {h && page === "lists" &&
            shelves.map((s) => {
              const on = s.productIds.includes(h.identity.productId);
              return (
                <button
                  key={s.id}
                  type="button"
                  className={row}
                  onClick={() =>
                    then(() =>
                      void toggle(s.id, h.identity.productId).then(
                        () => toast(on ? `Removed from ${s.name}` : `Added to ${s.name}`),
                        (e: Error) => toast.error(e.message),
                      ),
                    )
                  }
                >
                  <span className="min-w-0 flex-1 truncate">{s.name}</span>
                  {on && <Check className="size-4 text-lime" strokeWidth={2.6} />}
                </button>
              );
            })}
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}
