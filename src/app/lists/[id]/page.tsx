"use client";

import { CheckCircle2, Layers, MinusCircle, MoreHorizontal, Pencil, Plus, Share, Tag, Trash2 } from "lucide-react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { ListAddDialog, ListItemPriceDialog, ListNameDialog, ListShareDialog } from "@/components/lists/list-dialogs";
import { EmptyPage, limePillClass, productHref, RowMoreIcon, rowMoreClass, shortName } from "@/components/lists/list-row";
import { listTotals, useListItems, useListMeta, useListShare, type ListItemInfo } from "@/components/lists/use-lists";
import { ErrorState } from "@/components/portfolio/error-state";
import { ProductImage } from "@/components/product/product-image";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { money } from "@/lib/format";
import { askingPrice, type ListMeta } from "@/lib/lists";
import { useStore } from "@/lib/store/collection-store";
import { useShelves } from "@/lib/store/shelves";
import { cn } from "@/lib/utils";

const PERCENTS = [100, 95, 90, 85, 80, 75, 70];

/** One list: its cards, what they're worth, and for a list you're selling, your asking prices (the app's `ListDetailView`). */
export default function ListPage() {
  const { id } = useParams<{ id: string }>();
  const listId = decodeURIComponent(id);
  const store = useStore();
  const router = useRouter();
  const { shelves, update, remove, toggle } = useShelves();
  const { meta, update: updateMeta, drop } = useListMeta();
  const list = shelves.find((s) => s.id === listId);
  const info = useListItems(list?.productIds ?? []);
  const share = useListShare(listId, false);
  const [adding, setAdding] = useState(false);
  const [sharing, setSharing] = useState(false);
  const [renaming, setRenaming] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [pricing, setPricing] = useState<string | null>(null);

  if (store.status === "loading") return <Skeleton className="h-96 w-full rounded-3xl" />;
  if (store.status === "error") return <ErrorState message={store.error} />;
  if (!list) {
    return (
      <EmptyPage
        icon={Layers}
        title="This list was deleted"
        line="It may have been removed on another device."
        action={
          <Link href="/lists" className={limePillClass}>
            Back to Lists
          </Link>
        }
      />
    );
  }

  const m: ListMeta = meta(listId);
  const forSale = m.forSale === true;
  const items = list.productIds.map(info);
  const totals = listTotals(items, m);
  const cards = Math.round(totals.cards);

  const menu = (
    <DropdownMenu>
      <DropdownMenuTrigger className="lists-glass flex size-[46px] shrink-0 items-center justify-center rounded-full outline-none focus-visible:ring-2 focus-visible:ring-ring" aria-label="More">
        <MoreHorizontal className="size-[18px]" />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem onSelect={() => setRenaming(true)}>
          <Pencil /> Rename
        </DropdownMenuItem>
        {items.length > 0 && (
          <DropdownMenuItem onSelect={() => setSharing(true)}>
            <Share /> Share
          </DropdownMenuItem>
        )}
        <DropdownMenuSeparator />
        <DropdownMenuItem className="text-down [&_svg]:text-down" onSelect={() => setDeleting(true)}>
          <Trash2 /> Delete list
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );

  return (
    <div className="animate-fade-in">
      {items.length === 0 ? (
        <>
          <div className="flex items-center justify-between gap-3">
            <h1 className="truncate text-[17px] font-semibold">{list.name}</h1>
            {menu}
          </div>
          <EmptyPage
            icon={Layers}
            title="Nothing on this list yet"
            line={"Add cards from your collection or anywhere in the catalog. You don't have to own them."}
            action={
              <button type="button" onClick={() => setAdding(true)} className={limePillClass}>
                <Plus strokeWidth={2.5} /> Add cards
              </button>
            }
          />
        </>
      ) : (
        <div className="space-y-6">
          <div className="space-y-2">
            <h1 className="font-display text-balance text-[34px] leading-[1.05]">{list.name}</h1>
            {forSale ? (
              <>
                <p className="font-display tabular text-[44px] leading-none text-lime">{money(totals.asking)}</p>
                <p className="tabular text-[14px] text-muted">
                  Asking for {cards} card{cards === 1 ? "" : "s"} · {money(totals.market)} at market
                </p>
              </>
            ) : (
              <p className="tabular text-[14px] text-muted">
                {cards} card{cards === 1 ? "" : "s"} · {money(totals.market)} at market
              </p>
            )}
          </div>

          <div className="flex items-center gap-2.5 sm:max-w-md">
            <button type="button" onClick={() => setAdding(true)} className="lists-glass inline-flex h-[46px] flex-1 items-center justify-center gap-1.5 rounded-full text-[15px] font-semibold">
              <Plus className="size-4" strokeWidth={2.5} /> Add cards
            </button>
            <button type="button" onClick={() => setSharing(true)} className="inline-flex h-[46px] flex-1 items-center justify-center gap-1.5 rounded-full bg-lime text-[15px] font-semibold text-[#0b0b0c]">
              <Share className="size-4" /> Share
            </button>
            {menu}
          </div>

          <section className="space-y-3.5 rounded-[18px] border border-border bg-surface p-4">
            <label className="flex items-center justify-between gap-4">
              <span>
                <span className="block text-[15px] font-semibold">For sale</span>
                <span className="block text-[12px] text-muted">Show asking prices on this list and its link</span>
              </span>
              <Switch checked={forSale} onCheckedChange={(on) => updateMeta(listId, (prev) => ({ ...prev, forSale: on }))} aria-label="For sale" />
            </label>
            {forSale && (
              <div className="space-y-2">
                <p className="font-mono text-[11px] uppercase tracking-[0.08em] text-muted">Asking, of market</p>
                <div className="fade-row flex gap-2 overflow-x-auto [scrollbar-width:none]" data-fade-end="true">
                  {PERCENTS.map((p) => (
                    <button
                      key={p}
                      type="button"
                      aria-pressed={(m.askPercent ?? 100) === p}
                      onClick={() => updateMeta(listId, (prev) => ({ ...prev, askPercent: p === 100 ? null : p }))}
                      className="lists-chip h-9 shrink-0 rounded-[13px] px-3.5 text-[14px] font-medium"
                    >
                      {p}%
                    </button>
                  ))}
                </div>
                <p className="text-[12px] text-subtle">Use a card&apos;s ⋯ to give it its own % or a set price.</p>
              </div>
            )}
          </section>

          <ul className="divide-y divide-border rounded-[18px] border border-border bg-surface px-3.5">
            {items.map((item) => (
              <Row
                key={item.productId}
                item={item}
                meta={m}
                forSale={forSale}
                onPrice={() => setPricing(item.productId)}
                onRemove={() =>
                  toggle(listId, item.productId).then(
                    () => toast(`Removed from ${list.name}`),
                    (e: Error) => toast.error(e.message),
                  )
                }
              />
            ))}
          </ul>
        </div>
      )}

      <ListAddDialog listId={listId} open={adding} onOpenChange={setAdding} />
      <ListShareDialog listId={listId} name={list.name} forSale={forSale} open={sharing} onOpenChange={setSharing} />
      <ListNameDialog open={renaming} onOpenChange={setRenaming} title="Rename list" action="Save" initial={list.name} onSave={(name) => update(listId, { name })} />
      <ListItemPriceDialog listId={listId} productId={pricing} product={pricing ? info(pricing).product : undefined} market={pricing ? info(pricing).market : null} onClose={() => setPricing(null)} />
      <Dialog open={deleting} onOpenChange={setDeleting}>
        <DialogContent hideClose className="gap-4 p-5 sm:max-w-sm">
          <DialogTitle className="text-center text-[17px] font-semibold">Delete {list.name}?</DialogTitle>
          <DialogDescription className="text-center text-[14px] text-muted">The list goes, and its share link stops working. Your cards stay in your collection.</DialogDescription>
          <button
            type="button"
            className="h-12 rounded-full bg-down text-[16px] font-semibold text-white"
            onClick={() =>
              remove(listId).then(
                () => {
                  void share.stop().catch(() => undefined);
                  drop(listId);
                  setDeleting(false);
                  router.push("/lists");
                },
                (e: Error) => toast.error(e.message),
              )
            }
          >
            Delete list
          </button>
          <button type="button" className="h-11 text-[15px] font-semibold text-muted hover:text-foreground" onClick={() => setDeleting(false)}>
            Cancel
          </button>
        </DialogContent>
      </Dialog>
    </div>
  );
}

function Row({ item, meta, forSale, onPrice, onRemove }: { item: ListItemInfo; meta: ListMeta; forSale: boolean; onPrice: () => void; onRemove: () => void }) {
  const asking = askingPrice(meta, item.productId, item.market);
  // Priced on its own (a set price or its own %), not by the list's %.
  const own = meta.prices?.[item.productId] != null || meta.percents?.[item.productId] != null;
  const detail = [item.product?.setName, item.copyLabel].filter(Boolean).join(" · ");
  return (
    <li className="flex items-center gap-3 py-2">
      <Link href={productHref(item.productId)} className="flex min-w-0 flex-1 items-center gap-3 py-1">
        <ProductImage product={item.product} size="xs" className="h-[62px] w-11 shrink-0" />
        <span className="min-w-0 flex-1">
          <span className="block truncate text-[14px] font-semibold">{item.product ? shortName(item.product) : "Loading…"}</span>
          <span className="block truncate text-[12px] text-muted">{detail}</span>
          {item.owned > 0 && (
            <span className="mt-0.5 flex items-center gap-1 text-[12px] text-muted">
              <CheckCircle2 className="size-3 fill-lime text-surface" aria-hidden />
              Owned{item.owned > 1 ? ` ×${item.owned}` : ""}
            </span>
          )}
        </span>
      </Link>
      {forSale ? (
        <button type="button" onClick={onPrice} className="flex flex-col items-end gap-0.5" aria-label={`Asking ${money(asking)}. Change price`}>
          <span className={cn("tabular rounded-lg border px-2 py-[3px] text-[15px] font-semibold", own ? "border-lime" : "border-border-strong")}>{money(asking)}</span>
          <span className="tabular text-[11px] text-muted">market {money(item.market)}</span>
        </button>
      ) : (
        <span className="tabular text-[15px] font-semibold">{money(item.market)}</span>
      )}
      {/* A small drop-down by the ⋯ (the owner's call: no sheet for two actions). */}
      <DropdownMenu>
        <DropdownMenuTrigger className={rowMoreClass} aria-label={`Actions for ${item.product?.name ?? "this card"}`}>
          <RowMoreIcon />
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          {forSale && (
            <DropdownMenuItem onSelect={onPrice}>
              <Tag /> Set its price
            </DropdownMenuItem>
          )}
          <DropdownMenuItem className="text-down [&_svg]:text-down" onSelect={onRemove}>
            <MinusCircle /> Remove from list
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </li>
  );
}
