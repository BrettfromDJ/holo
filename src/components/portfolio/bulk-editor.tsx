"use client";

import { Briefcase, Check, Copy, Library, Trash2 } from "lucide-react";
import { memo, useState } from "react";
import { toast } from "sonner";
import { HoldingListRow, HoldingTile } from "@/components/portfolio/holding-items";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { undoToast } from "@/components/ui/undo-toast";
import type { HoldingView } from "@/lib/finance/portfolio";
import { liveEntries, restoreEntry, voidEntry } from "@/lib/holding-actions";
import { useStore } from "@/lib/store/collection-store";
import { MAIN, MAIN_NAME, usePortfolios } from "@/lib/store/portfolios";
import { useShelves } from "@/lib/store/shelves";
import { cn } from "@/lib/utils";

const items = (n: number) => `${n} item${n === 1 ? "" : "s"}`;

/** The check on a tile in select mode: a lime circle with a dark check, or a faint outline. */
export function SelectCheck({ selected, className }: { selected: boolean; className?: string }) {
  return (
    <span
      aria-hidden
      className={cn(
        "flex size-7 items-center justify-center rounded-full transition-colors",
        selected ? "bg-lime text-[#0b0b0c]" : "bg-background/60 ring-1 ring-inset ring-foreground/40 backdrop-blur",
        className,
      )}
    >
      {selected && <Check className="size-4" strokeWidth={3} />}
    </span>
  );
}

/**
 * A collection tile or list row. In select mode a click toggles it instead of opening it.
 * Memoized, so toggling one only redraws that one (`onToggle` and `onOpen` must be stable).
 */
export const SelectableHolding = memo(function SelectableHolding({
  h,
  view,
  selecting,
  selected,
  onToggle,
  onOpen,
}: {
  h: HoldingView;
  view: "grid" | "list";
  selecting: boolean;
  selected: boolean;
  onToggle: (key: string) => void;
  onOpen: (h: HoldingView) => void;
}) {
  const item = view === "grid" ? <HoldingTile h={h} onOpen={onOpen} /> : <HoldingListRow h={h} onOpen={onOpen} />;
  if (!selecting) return item;
  return (
    <div className="relative">
      <div className={cn("transition-opacity duration-150", !selected && "opacity-50")}>{item}</div>
      <button
        type="button"
        aria-pressed={selected}
        aria-label={`${selected ? "Deselect" : "Select"} ${h.product?.name ?? "item"}`}
        onClick={() => onToggle(h.key)}
        className="absolute inset-0 z-10 rounded-2xl outline-none focus-visible:ring-2 focus-visible:ring-lime"
      >
        <SelectCheck selected={selected} className={cn("absolute", view === "grid" ? "right-2.5 top-2.5" : "left-1.5 top-1.5")} />
      </button>
    </div>
  );
});

/**
 * The bar along the bottom in select mode: Move or Copy to a portfolio, Add to a shelf,
 * Delete. Sticks to the bottom of the page above the mobile tab bar; toasts stay bottom-right.
 */
export function BulkBar({
  selected,
  shownCount,
  onSelectAll,
  onSelectNone,
  onDone,
}: {
  selected: HoldingView[];
  shownCount: number;
  onSelectAll: () => void;
  onSelectNone: () => void;
  onDone: () => void;
}) {
  const { addTransaction, data } = useStore();
  const { portfolios, moveMany, copyMany } = usePortfolios();
  const { shelves, addMany } = useShelves();
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const n = selected.length;
  const all = n === shownCount && n > 0;
  const targets = [{ id: MAIN, name: MAIN_NAME }, ...portfolios];

  const run = async (work: () => Promise<void>, failure: string) => {
    setBusy(true);
    try {
      await work();
    } catch (err) {
      toast.error(failure, { description: err instanceof Error ? err.message : undefined });
    } finally {
      setBusy(false);
    }
  };

  const keys = () => selected.map((h) => h.key);

  const remove = () =>
    run(async () => {
      const live = selected.flatMap((h) => liveEntries(data.transactions, h.key));
      for (const t of live) await addTransaction(voidEntry(t));
      setConfirming(false);
      onDone();
      undoToast(`Deleted ${items(n)} from your collection`, async () => {
        for (const t of live) await addTransaction(restoreEntry(t));
      });
    }, "Couldn't delete");

  return (
    <>
      <div className="pointer-events-none sticky bottom-[calc(env(safe-area-inset-bottom)+80px)] z-30 mt-6 flex justify-center lg:bottom-6">
        <div className="pointer-events-auto flex max-w-full flex-wrap items-center justify-center gap-1.5 rounded-[22px] border border-border bg-surface/85 p-2 shadow-[0_12px_40px_-12px_rgba(0,0,0,0.7)] backdrop-blur-xl">
          <span className="tabular px-2 text-[13px] font-semibold">{n} selected</span>
          <Button variant="outline" size="sm" className="mx-1 px-4" onClick={all ? onSelectNone : onSelectAll}>
            {all ? "Select none" : "Select all"}
          </Button>
          {/* A clear gap before the actions, so Select all is never a slip away from Delete. */}
          <span aria-hidden className="mx-2 h-5 w-px bg-border" />
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="secondary" size="sm" disabled={!n || busy}>
                <Briefcase /> Move
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="center" side="top">
              <DropdownMenuLabel>Move to portfolio</DropdownMenuLabel>
              {targets.map((p) => (
                <DropdownMenuItem key={p.id} onSelect={() => void run(async () => { await moveMany(keys(), p.id); toast(`Moved ${items(n)} to ${p.name}`); }, "Couldn't move")}>
                  {p.name}
                </DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="secondary" size="sm" disabled={!n || busy}>
                <Copy /> Copy
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="center" side="top">
              <DropdownMenuLabel>Also show in</DropdownMenuLabel>
              {targets.map((p) => (
                <DropdownMenuItem key={p.id} onSelect={() => void run(async () => { await copyMany(keys(), p.id); toast(`${items(n)} also in ${p.name}`); }, "Couldn't copy")}>
                  {p.name}
                </DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="secondary" size="sm" disabled={!n || busy || !shelves.length}>
                <Library /> List
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="center" side="top">
              <DropdownMenuLabel>Add to list</DropdownMenuLabel>
              {shelves.map((s) => (
                <DropdownMenuItem
                  key={s.id}
                  onSelect={() =>
                    void run(async () => {
                      await addMany(s.id, selected.map((h) => h.identity.productId));
                      toast(`Added ${items(n)} to ${s.name}`);
                    }, "Couldn't add to list")
                  }
                >
                  {s.name}
                </DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>
          <Button variant="danger" size="sm" disabled={!n || busy} onClick={() => setConfirming(true)}>
            <Trash2 /> Delete
          </Button>
          <span aria-hidden className="mx-0.5 h-5 w-px bg-border" />
          <Button variant="lime" size="sm" onClick={onDone}>
            Done
          </Button>
        </div>
      </div>
      <Dialog open={confirming} onOpenChange={(o) => !busy && setConfirming(o)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete {items(n)}?</DialogTitle>
            <DialogDescription>Their purchase and sale records are removed. They leave your value, cost and gains.</DialogDescription>
          </DialogHeader>
          <div className="flex gap-2 px-6 pb-6 pt-4">
            <Button variant="secondary" size="lg" className="flex-1" onClick={() => setConfirming(false)} disabled={busy}>
              Cancel
            </Button>
            <Button variant="danger" size="lg" className="flex-1" onClick={() => void remove()} disabled={busy}>
              {busy ? "Deleting…" : `Delete ${items(n)}`}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}
