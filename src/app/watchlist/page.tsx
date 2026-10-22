"use client";

import { BellDot, Eye, MoreHorizontal, Plus, ShoppingBag, Target, Trash2 } from "lucide-react";
import Link from "next/link";
import { useState } from "react";
import { toast } from "sonner";
import { MoneyInput, parseMoney } from "@/components/flows/fields";
import { ErrorState } from "@/components/portfolio/error-state";
import { DeltaPill } from "@/components/product/delta";
import { ProductImage } from "@/components/product/product-image";
import { PageHeader } from "@/components/shell/page-header";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Skeleton } from "@/components/ui/skeleton";
import { categoryOf } from "@/lib/catalog";
import { money, signedPct } from "@/lib/format";
import { useStore } from "@/lib/store/collection-store";
import { priceKey, type WatchlistItem } from "@/lib/types";

export default function WatchlistPage() {
  const store = useStore();
  const [editing, setEditing] = useState<WatchlistItem | null>(null);

  if (store.status === "loading") return <Skeleton className="h-96 w-full rounded-[var(--radius-card)]" />;
  if (store.status === "error") return <ErrorState message={store.error} />;

  const items = store.data.watchlist;

  return (
    <div className="animate-fade-in">
      <PageHeader
        title="Watchlist"
        subtitle="Products you're considering. Tracked separately — never part of your portfolio value."
        actions={
          <Button variant="primary" onClick={() => store.openAdd({ watch: true })}>
            <Plus /> Watch a product
          </Button>
        }
      />

      {!items.length ? (
        <div className="flex flex-col items-center py-20 text-center">
          <span className="flex size-14 items-center justify-center rounded-xl bg-surface-2">
            <Eye className="size-6 text-muted" />
          </span>
          <p className="mt-5 text-[18px] font-semibold">Nothing on your watchlist</p>
          <p className="mt-1 max-w-sm text-[15px] text-muted">Watch products to follow their prices and get a heads-up when they reach your target.</p>
          <Button variant="primary" size="lg" className="mt-6" onClick={() => store.openAdd({ watch: true })}>
            <Plus /> Watch a product
          </Button>
        </div>
      ) : (
        <Card className="overflow-hidden">
          <div className="hidden grid-cols-[3.5rem_minmax(0,2fr)_repeat(4,minmax(0,1fr))_2.5rem] gap-4 border-b border-border px-4 py-3 text-[12px] font-medium text-subtle md:grid">
            <span />
            <span>Product</span>
            <span className="text-right">Price</span>
            <span className="text-right">7D</span>
            <span className="text-right">30D</span>
            <span className="text-right">Target</span>
            <span />
          </div>
          <ul className="divide-y divide-border">
            {items.map((w) => {
              const p = store.data.products[w.productId];
              const price = store.data.prices[priceKey(w.productId, w.printing)];
              const market = price?.market ?? null;
              const hit = market !== null && w.targetPrice !== null && market <= w.targetPrice;
              const gap = market !== null && w.targetPrice !== null && w.targetPrice > 0 ? (market - w.targetPrice) / w.targetPrice : null;
              return (
                <li key={w.id} className="grid grid-cols-[3rem_1fr_auto] items-center gap-4 px-4 py-3 md:grid-cols-[3.5rem_minmax(0,2fr)_repeat(4,minmax(0,1fr))_2.5rem]">
                  <Link href={`/product/${encodeURIComponent(w.productId)}`}>
                    <ProductImage product={p} size="xs" className="size-12 rounded-lg md:size-14" />
                  </Link>
                  <Link href={`/product/${encodeURIComponent(w.productId)}`} className="min-w-0">
                    <p className="truncate text-[14px] font-medium">{p?.name ?? w.productId}</p>
                    <p className="truncate text-[12px] text-muted">{[p?.setName, p ? categoryOf(p) : null].filter(Boolean).join(" · ")}</p>
                    {hit && (
                      <Badge variant="up" className="mt-1">
                        <BellDot /> At or below target
                      </Badge>
                    )}
                  </Link>
                  <div className="text-right md:contents">
                    <p className="tabular text-[14px] font-medium md:text-right">{money(market)}</p>
                    <div className="md:text-right">
                      <DeltaPill ratio={price?.change7dPct != null ? price.change7dPct / 100 : null} />
                    </div>
                    <div className="hidden md:block md:text-right">
                      <DeltaPill ratio={price?.change30dPct != null ? price.change30dPct / 100 : null} />
                    </div>
                    <button onClick={() => setEditing(w)} className="hidden text-right md:block" aria-label="Edit target price">
                      <p className="tabular text-[14px]">{w.targetPrice !== null ? money(w.targetPrice) : <span className="text-subtle">Set target</span>}</p>
                      {gap !== null && <p className="tabular text-[11px] text-muted">{gap > 0 ? `${signedPct(gap, 1)} above` : "Reached"}</p>}
                    </button>
                  </div>
                  <div className="col-start-3 row-start-1 hidden md:col-auto md:row-auto md:block">
                    <RowMenu w={w} onEdit={() => setEditing(w)} />
                  </div>
                  <div className="col-span-3 flex justify-end gap-2 md:hidden">
                    <Button size="sm" variant="secondary" onClick={() => setEditing(w)}>
                      <Target /> {w.targetPrice !== null ? money(w.targetPrice) : "Target"}
                    </Button>
                    <Button size="sm" variant="secondary" onClick={() => store.openAdd({ productId: w.productId, fromWatchId: w.id })}>
                      <ShoppingBag /> Bought it
                    </Button>
                    <RowMenu w={w} onEdit={() => setEditing(w)} />
                  </div>
                </li>
              );
            })}
          </ul>
        </Card>
      )}
      <TargetDialog item={editing} onClose={() => setEditing(null)} />
    </div>
  );
}

function RowMenu({ w, onEdit }: { w: WatchlistItem; onEdit: () => void }) {
  const { openAdd, removeWatch } = useStore();
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon-sm" aria-label="Watchlist actions">
          <MoreHorizontal />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem onSelect={() => openAdd({ productId: w.productId, fromWatchId: w.id })}>
          <ShoppingBag /> Move to collection
        </DropdownMenuItem>
        <DropdownMenuItem onSelect={onEdit}>
          <Target /> Set target price
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem
          onSelect={async () => {
            await removeWatch(w.id);
            toast("Removed from watchlist");
          }}
        >
          <Trash2 /> Remove
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

function TargetDialog({ item, onClose }: { item: WatchlistItem | null; onClose: () => void }) {
  const { updateWatch, data } = useStore();
  const [value, setValue] = useState("");
  const product = item ? data.products[item.productId] : undefined;
  return (
    <Dialog
      open={item !== null}
      onOpenChange={(o) => {
        if (o && item) setValue(item.targetPrice !== null ? item.targetPrice.toFixed(2) : "");
        if (!o) onClose();
      }}
    >
      <DialogContent onOpenAutoFocus={() => item && setValue(item.targetPrice !== null ? item.targetPrice.toFixed(2) : "")}>
        <form
          onSubmit={async (e) => {
            e.preventDefault();
            if (!item) return;
            await updateWatch(item.id, { targetPrice: parseMoney(value) });
            toast.success("Target updated");
            onClose();
          }}
        >
          <DialogHeader>
            <DialogTitle>Target price</DialogTitle>
            <DialogDescription>{product?.name}</DialogDescription>
          </DialogHeader>
          <div className="px-6 py-4">
            <MoneyInput value={value} onChange={setValue} autoFocus ariaLabel="Target price" placeholder="Leave empty for none" />
          </div>
          <div className="px-6 pb-6">
            <Button type="submit" variant="primary" size="lg" className="w-full">
              Save
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
