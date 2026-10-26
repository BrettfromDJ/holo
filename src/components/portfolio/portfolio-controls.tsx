"use client";

import { Briefcase, Check, ChevronsUpDown, Pencil, Plus, Trash2 } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { ALL, MAIN, MAIN_NAME, usePortfolios, type Portfolio } from "@/lib/store/portfolios";
import { cn } from "@/lib/utils";

/** Name a new portfolio or rename one. */
export function PortfolioDialog({ open, onOpenChange, portfolio, onSaved }: { open: boolean; onOpenChange: (o: boolean) => void; portfolio?: Portfolio | null; onSaved?: (p: Portfolio) => void }) {
  const { create, rename } = usePortfolios();
  const [name, setName] = useState("");
  const [saving, setSaving] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  useEffect(() => {
    if (open) setName(portfolio?.name ?? "");
  }, [open, portfolio]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    const n = name.trim();
    if (!n) return;
    setSaving(true);
    try {
      if (portfolio) {
        await rename(portfolio.id, n);
        onSaved?.({ ...portfolio, name: n });
      } else {
        const p = await create(n);
        onSaved?.(p);
        toast.success(`Portfolio “${n}” created`, { description: "Move holdings into it from their product page." });
      }
      onOpenChange(false);
    } catch (err) {
      toast.error("Couldn't save portfolio", { description: (err as Error).message });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        className="p-6"
        onOpenAutoFocus={(e) => {
          e.preventDefault();
          inputRef.current?.focus();
        }}
      >
        <DialogTitle className="text-[17px] font-semibold">{portfolio ? "Rename portfolio" : "New portfolio"}</DialogTitle>
        <DialogDescription className="mt-1 text-[13px] text-muted">Keep holdings apart — e.g. your personal collection and resale inventory — each with its own totals and gains.</DialogDescription>
        <form onSubmit={submit} className="mt-5 space-y-4">
          <Input ref={inputRef} value={name} onChange={(e) => setName(e.target.value)} maxLength={40} placeholder="e.g. Resale inventory" aria-label="Portfolio name" />
          <div className="flex justify-end gap-2">
            <Button type="button" variant="ghost" onClick={() => onOpenChange(false)}>
              Cancel
            </Button>
            <Button type="submit" variant="primary" disabled={!name.trim() || saving}>
              {portfolio ? "Save" : "Create portfolio"}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}

/** Pick which portfolio every view shows. */
export function PortfolioSwitcher({ className, compact }: { className?: string; compact?: boolean }) {
  const { portfolios, selected, select, nameOf } = usePortfolios();
  const [creating, setCreating] = useState(false);
  // The compact (mobile) switcher only appears once there is something to switch between.
  if (compact && !portfolios.length) return null;
  const options = [{ id: ALL, name: "All portfolios" }, { id: MAIN, name: MAIN_NAME }, ...portfolios];
  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger
          className={cn(
            "flex items-center gap-2 rounded-xl border border-border bg-surface text-left transition-colors hover:bg-surface-2",
            compact ? "h-9 px-3 text-[13px]" : "w-full px-3 py-2.5",
            selected !== ALL && "border-border-strong",
            className,
          )}
        >
          <Briefcase className="size-4 shrink-0 text-muted" />
          <span className="min-w-0 flex-1 truncate text-[13px] font-medium">{nameOf(selected)}</span>
          <ChevronsUpDown className="size-4 shrink-0 text-subtle" />
        </DropdownMenuTrigger>
        <DropdownMenuContent align="start" className="w-[216px]">
          <DropdownMenuLabel>Portfolio</DropdownMenuLabel>
          {options.map((o) => (
            <DropdownMenuItem key={o.id} onSelect={() => select(o.id)}>
              <span className="flex-1 truncate">{o.name}</span>
              {selected === o.id && <Check className="size-4" />}
            </DropdownMenuItem>
          ))}
          <DropdownMenuSeparator />
          <DropdownMenuItem onSelect={() => window.setTimeout(() => setCreating(true), 0)}>
            <Plus className="size-4" /> New portfolio…
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      <PortfolioDialog open={creating} onOpenChange={setCreating} />
    </>
  );
}

/** Shown on Overview and Collection while one portfolio is selected. */
export function PortfolioBanner() {
  const { selected, nameOf, select } = usePortfolios();
  if (selected === ALL) return null;
  return (
    <p className="mb-4 flex items-center gap-2 text-[13px] text-muted">
      <Briefcase className="size-3.5" />
      Showing <span className="font-medium text-foreground">{nameOf(selected)}</span> only ·
      <button onClick={() => select(ALL)} className="font-medium underline-offset-4 hover:text-foreground hover:underline">
        Show all
      </button>
    </p>
  );
}

/** Move a holding between portfolios (product page). */
export function MoveToPortfolio({ holdingKey }: { holdingKey: string }) {
  const { portfolios, portfolioOf, nameOf, move } = usePortfolios();
  if (!portfolios.length) return null;
  const current = portfolioOf(holdingKey);
  return (
    <DropdownMenu>
      <DropdownMenuTrigger className="inline-flex items-center gap-1 rounded-full bg-surface-2 px-2.5 py-1 text-[12px] text-muted hover:text-foreground">
        <Briefcase className="size-3" /> {nameOf(current)}
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuLabel>Move to portfolio</DropdownMenuLabel>
        {[{ id: MAIN, name: MAIN_NAME }, ...portfolios].map((p) => (
          <DropdownMenuItem
            key={p.id}
            onSelect={() =>
              move(holdingKey, p.id).then(
                () => toast(`Moved to ${p.name}`),
                (e: Error) => toast.error(e.message),
              )
            }
          >
            <span className="flex-1">{p.name}</span>
            {current === p.id && <Check className="size-4" />}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

/** Settings section: create, rename and delete portfolios. */
export function PortfolioManager() {
  const { portfolios, remove, error } = usePortfolios();
  const [dialog, setDialog] = useState<{ portfolio: Portfolio | null } | null>(null);
  return (
    <div>
      <div className="flex items-center justify-between gap-3 px-5 py-4">
        <div className="min-w-0">
          <p className="text-[15px] font-medium">{MAIN_NAME}</p>
          <p className="mt-0.5 text-[13px] text-muted">Everything not in another portfolio</p>
        </div>
      </div>
      {portfolios.map((p) => (
        <div key={p.id} className="flex items-center justify-between gap-3 border-t border-border px-5 py-4">
          <div className="min-w-0">
            <p className="truncate text-[15px] font-medium">{p.name}</p>
            <p className="mt-0.5 text-[13px] text-muted">
              {p.holdingKeys.length} holding{p.holdingKeys.length === 1 ? "" : "s"}
            </p>
          </div>
          <div className="flex gap-1">
            <Button variant="ghost" size="icon-sm" aria-label={`Rename ${p.name}`} onClick={() => setDialog({ portfolio: p })}>
              <Pencil />
            </Button>
            <Button
              variant="ghost"
              size="icon-sm"
              aria-label={`Delete ${p.name}`}
              onClick={() => {
                if (!confirm(`Delete “${p.name}”? Its holdings move back to ${MAIN_NAME}; nothing is sold or removed.`)) return;
                void remove(p.id).catch((e: Error) => toast.error(e.message));
              }}
            >
              <Trash2 />
            </Button>
          </div>
        </div>
      ))}
      <div className="border-t border-border px-5 py-4">
        {error ? (
          <p className="text-[13px] text-down">{error}</p>
        ) : (
          <Button variant="secondary" onClick={() => setDialog({ portfolio: null })}>
            <Plus /> New portfolio
          </Button>
        )}
      </div>
      <PortfolioDialog open={dialog !== null} onOpenChange={(o) => !o && setDialog(null)} portfolio={dialog?.portfolio ?? null} />
    </div>
  );
}
