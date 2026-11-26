"use client";

import { ExternalLink, Heart, HeartOff, Plus } from "lucide-react";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import { EmptyPage, limePillClass, ListPageTitle, listPrice, ListRow, productHref, RowMoreIcon, rowMoreClass, SelectBar, SelectToggle } from "@/components/lists/list-row";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Skeleton } from "@/components/ui/skeleton";
import { useStore } from "@/lib/store/collection-store";
import { useWishlist, type WishItem } from "@/lib/store/wishlist";
import { priceKey } from "@/lib/types";

/** Latest saved price for a catalog product (no TCG API requests). */
async function catalogPrice(w: WishItem): Promise<number | null | undefined> {
  const res = await fetch(`/api/explore/products/${encodeURIComponent(w.product.id)}`);
  if (!res.ok) return undefined;
  const { prices } = (await res.json()) as { prices: { printing: string | null; market: number | null }[] };
  const match = prices.find((p) => p.printing === w.printing && p.market !== null) ?? prices.find((p) => p.market !== null);
  return match ? match.market : undefined;
}

/**
 * Cards you want next (the app's Wishlist): plain rows, newest first, each with the price, today's
 * move and how much it has moved since you added it. The share link (/w/<token>) still works for
 * links already made; the page itself no longer offers sharing, like the app.
 */
export default function WishlistPage() {
  const store = useStore();
  const { items, ready, setPrices, remove } = useWishlist();
  const [selecting, setSelecting] = useState(false);
  const [chosen, setChosen] = useState<Set<string>>(new Set());

  // Once per visit, bring each price up to date from saved prices.
  const [refreshed, setRefreshed] = useState(false);
  useEffect(() => {
    if (!ready || refreshed || store.status !== "ready") return;
    setRefreshed(true);
    void (async () => {
      const prices = new Map<string, number | null>();
      await Promise.all(
        items.map(async (w) => {
          const local = store.data.prices[priceKey(w.product.id, w.printing)];
          if (local && local.market !== null) return prices.set(w.product.id, local.market);
          if (w.product.id.startsWith("sample:")) return;
          const latest = await catalogPrice(w).catch(() => undefined);
          if (latest !== undefined) prices.set(w.product.id, latest);
        }),
      );
      if (prices.size) setPrices(prices);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps -- once per visit, after the list loads
  }, [ready, refreshed, store.status]);

  // Newest first; no sort control (the owner's call).
  const sorted = useMemo(() => [...items].sort((a, b) => b.addedAt.localeCompare(a.addedAt)), [items]);

  const removeWishes = (productIds: string[]) => {
    for (const id of productIds) remove(id);
    toast(productIds.length === 1 ? "Removed from your wishlist" : `Removed ${productIds.length} cards from your wishlist`);
  };

  const toggleSelecting = () => {
    setSelecting((s) => !s);
    setChosen(new Set());
  };

  return (
    <div className={selecting ? "animate-fade-in pb-28" : "animate-fade-in"}>
      <ListPageTitle title="Wishlist" right={items.length > 0 || selecting ? <SelectToggle selecting={selecting} onClick={toggleSelecting} /> : null} />

      {!ready ? (
        <div className="space-y-2">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-[95px] rounded-2xl" />
          ))}
        </div>
      ) : !items.length ? (
        <EmptyPage
          icon={Heart}
          title="Your wishlist is empty"
          line={"Open any card and tap Add to wishlist to keep track of what you want next."}
          action={
            <Link href="/explore" className={limePillClass}>
              Explore cards
            </Link>
          }
        />
      ) : (
        <ul className="space-y-2">
          {sorted.map((w) => {
            const live = listPrice(store.data.prices, w.product.id, w.printing);
            return (
              <ListRow
                key={w.id}
                productId={w.product.id}
                product={w.product}
                price={live?.market ?? w.price}
                change24hPct={live?.change24hPct}
                target={w.target}
                addedPrice={w.addedPrice}
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
                    <DropdownMenuTrigger className={rowMoreClass} aria-label={`Actions for ${w.product.name}`}>
                      <RowMoreIcon />
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem asChild>
                        <Link href={productHref(w.product.id)}>
                          <ExternalLink /> Open card
                        </Link>
                      </DropdownMenuItem>
                      <DropdownMenuItem asChild>
                        <Link href={productHref(w.product.id)}>
                          <Plus /> Add to collection
                        </Link>
                      </DropdownMenuItem>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem className="text-down [&_svg]:text-down" onSelect={() => removeWishes([w.product.id])}>
                        <HeartOff /> Remove from wishlist
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
          label={(n) => `Remove ${n}`}
          onAll={() => setChosen(chosen.size === items.length ? new Set() : new Set(items.map((w) => w.id)))}
          onRemove={() => {
            const ids = items.filter((w) => chosen.has(w.id)).map((w) => w.product.id);
            setSelecting(false);
            setChosen(new Set());
            removeWishes(ids);
          }}
        />
      )}
    </div>
  );
}
