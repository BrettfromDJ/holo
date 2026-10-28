"use client";

import { Hint } from "@/components/ui/tooltip";
import { Check, Library, Plus } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { useShelves, type Shelf } from "@/lib/store/shelves";

/** Create or rename a shelf. `onSaved` receives the new or edited shelf. */
export function ShelfDialog({
  open,
  onOpenChange,
  shelf,
  initialProductIds,
  onSaved,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  shelf?: Shelf | null;
  initialProductIds?: string[];
  onSaved?: (shelf: Shelf) => void;
}) {
  const { create, update } = useShelves();
  const [name, setName] = useState("");
  const [saving, setSaving] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!open) return;
    setName(shelf?.name ?? "");
  }, [open, shelf]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    const n = name.trim();
    if (!n) return;
    setSaving(true);
    try {
      if (shelf) {
        await update(shelf.id, { name: n });
        onSaved?.({ ...shelf, name: n });
      } else {
        const created = await create(n, initialProductIds);
        onSaved?.(created);
        toast.success(`Shelf “${n}” created`);
      }
      onOpenChange(false);
    } catch (err) {
      toast.error("Couldn't save shelf", { description: err instanceof Error ? err.message : undefined });
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
        <DialogTitle className="text-[17px] font-semibold">{shelf ? "Edit shelf" : "New shelf"}</DialogTitle>
        <DialogDescription className="mt-1 text-[13px] text-muted">Group products your way — grails, things to open, things to sell.</DialogDescription>
        <form onSubmit={submit} className="mt-5 space-y-4">
          <Input ref={inputRef} value={name} onChange={(e) => setName(e.target.value)} maxLength={40} placeholder="e.g. Grails" aria-label="Shelf name" />
          <div className="flex justify-end gap-2">
            <Button type="button" variant="ghost" onClick={() => onOpenChange(false)}>
              Cancel
            </Button>
            <Button type="submit" variant="primary" disabled={!name.trim() || saving}>
              {shelf ? "Save" : "Create shelf"}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}

/** Product-page menu for putting a product on (or taking it off) shelves. */
export function ShelfMenu({ productId, compact }: { productId: string; compact?: boolean }) {
  const { shelves, toggle, error } = useShelves();
  const [creating, setCreating] = useState(false);
  const on = shelves.filter((s) => s.productIds.includes(productId));

  return (
    <>
      <DropdownMenu>
        {compact ? (
          <Hint content={on.length ? `On ${on.length} shelf${on.length === 1 ? "" : "s"}` : "Add to shelf"}>
            <DropdownMenuTrigger asChild>
              <Button variant="secondary" size="icon" aria-label={on.length ? `On ${on.length} shelf${on.length === 1 ? "" : "s"}` : "Add to shelf"} className="relative">
                <Library />
                {on.length > 0 && <span className="absolute right-1.5 top-1.5 size-1.5 rounded-full bg-foreground" aria-hidden />}
              </Button>
            </DropdownMenuTrigger>
          </Hint>
        ) : (
          <DropdownMenuTrigger asChild>
            <Button variant="secondary">
              <Library /> {on.length ? `On ${on.length} shelf${on.length === 1 ? "" : "s"}` : "Add to shelf"}
            </Button>
          </DropdownMenuTrigger>
        )}
        <DropdownMenuContent align="end" className="w-60">
          <DropdownMenuLabel>Shelves</DropdownMenuLabel>
          {error && <p className="px-2 py-1.5 text-[12px] text-down">{error}</p>}
          {shelves.map((s) => {
            const checked = s.productIds.includes(productId);
            return (
              <DropdownMenuItem
                key={s.id}
                onSelect={(e) => {
                  e.preventDefault();
                  toggle(s.id, productId).then(
                    () => toast(checked ? `Removed from ${s.name}` : `Added to ${s.name}`),
                    (err: Error) => toast.error(err.message),
                  );
                }}
              >
                <span className="flex-1 truncate">{s.name}</span>
                {checked && <Check className="size-4" />}
              </DropdownMenuItem>
            );
          })}
          {shelves.length > 0 && <DropdownMenuSeparator />}
          <DropdownMenuItem onSelect={() => window.setTimeout(() => setCreating(true), 0)} disabled={Boolean(error)}>
            <Plus className="size-4" /> New shelf…
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      <ShelfDialog open={creating} onOpenChange={setCreating} initialProductIds={[productId]} />
    </>
  );
}
