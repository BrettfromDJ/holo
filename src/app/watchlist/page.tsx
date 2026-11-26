"use client";

import { Eye, EyeOff, Target } from "lucide-react";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import { MoneyInput, parseMoney } from "@/components/flows/fields";
import { EmptyPage, limePillClass, ListPageTitle, listPrice, ListRow, RowMoreIcon, rowMoreClass, SelectBar, SelectToggle } from "@/components/lists/list-row";
import { ErrorState } from "@/components/portfolio/error-state";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Skeleton } from "@/components/ui/skeleton";
import { money } from "@/lib/format";
import { useStore } from "@/lib/store/collection-store";
import type { WatchlistItem } from "@/lib/types";

export default function WatchlistPage() {
  const store = useStore();
  const [editing, setEditing] = useState<WatchlistItem | null>(null);
  const [selecting, setSelecting] = useState(false);
  const [chosen, setChosen] = useState<Set<string>>(new Set());

  // Newest first; no sort control (the owner's call).
  const items = useMemo(() => [...store.data.watchlist].sort((a, b) => b.addedAt.localeCompare(a.addedAt)), [store.data.watchlist]);

  // Cards watched since the collection loaded: their details and saved prices (our DB, not TCG API).
  const missing = items.filter((w) => !store.data.products[w.productId] && !w.productId.startsWith("sample:")).map((w) => w.productId);
  const missingKey = missing.join(",");
  useEffect(() => {
    if (store.status !== "ready" || !missingKey) return;
    for (const id of missingKey.split(",")) void store.showCatalogProduct(id).catch(() => false);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only when the missing set changes
  }, [missingKey, store.status]);

  if (store.status === "loading") return <Skeleton className="h-96 w-full rounded-3xl" />;
  if (store.status === "error") return <ErrorState message={store.error} />;

  const toggleSelecting = () => {
    setSelecting((s) => !s);
    setChosen(new Set());
  };

  const stopWatching = async (ids: string[]) => {
    try {
      for (const id of ids) await store.removeWatch(id);
      toast(ids.length === 1 ? "Removed from your watchlist" : `Stopped watching ${ids.length} cards`);
    } catch (e) {
      toast.error("Couldn't update your watchlist", { description: e instanceof Error ? e.message : undefined });
    }
  };

  return (
    <div className={selecting ? "animate-fade-in pb-28" : "animate-fade-in"}>
      <ListPageTitle title="Watchlist" right={items.length > 0 || selecting ? <SelectToggle selecting={selecting} onClick={toggleSelecting} /> : null} />

      {!items.length ? (
        <EmptyPage
          icon={Eye}
          title="Watch a card's price"
          line={"Open any card and tap Watch price. Set a target and you'll hear when it drops to what you'd\u00a0pay."}
          action={
            <Link href="/explore" className={limePillClass}>
              Explore cards
            </Link>
          }
        />
      ) : (
        <ul className="space-y-2">
          {items.map((w) => {
            const price = listPrice(store.data.prices, w.productId, w.printing);
            return (
              <ListRow
                key={w.id}
                productId={w.productId}
                product={store.data.products[w.productId]}
                price={price?.market ?? null}
                change24hPct={price?.change24hPct}
                target={w.targetPrice}
                selecting={selecting}
                selected={chosen.has(w.id)}
                onToggle={() =>
                  setChosen((s) => {
                    const next = new Set(s);
                    if (next.has(w.id)) next.delete(w.id);
                    else next.add(w.id);
                    return next;
                  })
                }
                more={
                  <DropdownMenu>
                    <DropdownMenuTrigger className={rowMoreClass} aria-label={`Actions for ${store.data.products[w.productId]?.name ?? "this card"}`}>
                      <RowMoreIcon />
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem onSelect={() => setEditing(w)}>
                        <Target /> {w.targetPrice === null ? "Set a target price" : "Edit target price"}
                      </DropdownMenuItem>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem className="text-down [&_svg]:text-down" onSelect={() => void stopWatching([w.id])}>
                        <EyeOff /> Stop watching
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                }
              />
            );
          })}
        </ul>
      )}

      {selecting && (
        <SelectBar
          total={items.length}
          chosen={chosen.size}
          label={(n) => `Stop watching ${n}`}
          onAll={() => setChosen(chosen.size === items.length ? new Set() : new Set(items.map((w) => w.id)))}
          onRemove={() => {
            const ids = [...chosen];
            setSelecting(false);
            setChosen(new Set());
            void stopWatching(ids);
          }}
        />
      )}
      <TargetDialog item={editing} onClose={() => setEditing(null)} />
    </div>
  );
}

function TargetDialog({ item, onClose }: { item: WatchlistItem | null; onClose: () => void }) {
  const { updateWatch, data } = useStore();
  const [value, setValue] = useState("");
  const product = item ? data.products[item.productId] : undefined;
  const market = item ? listPrice(data.prices, item.productId, item.printing)?.market ?? null : null;
  useEffect(() => {
    if (item) setValue(item.targetPrice !== null ? item.targetPrice.toFixed(2) : "");
  }, [item]);
  return (
    <Dialog open={item !== null} onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
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
            <DialogDescription>
              {product?.name}
              {market !== null && ` · market now ${money(market)}`}
            </DialogDescription>
          </DialogHeader>
          <div className="px-6 py-4">
            <MoneyInput value={value} onChange={setValue} autoFocus ariaLabel="Target price" placeholder="Leave empty for none" />
            <p className="mt-2 text-[13px] text-muted">With a target, you get a notification when the daily price check finds it at or below it.</p>
          </div>
          <div className="px-6 pb-6">
            <Button type="submit" variant="lime" size="lg" className="w-full rounded-full">
              Save
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
