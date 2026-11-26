"use client";

import { Plus } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { ListNameDialog } from "@/components/lists/list-dialogs";
import { ListPlaceholderFan, ListTile, TrackingPanel } from "@/components/lists/list-tile";
import { useListItems, useListMeta } from "@/components/lists/use-lists";
import { ErrorState } from "@/components/portfolio/error-state";
import { Skeleton } from "@/components/ui/skeleton";
import { useStore } from "@/lib/store/collection-store";
import { useShelves } from "@/lib/store/shelves";
import { useWishlist } from "@/lib/store/wishlist";

/** Every list (favorites, want lists, cards to sell at a show) and the built-in watchlist and wishlist (the app's `ListsHomeView`). */
export default function ListsPage() {
  const store = useStore();
  const router = useRouter();
  const { shelves, error, create } = useShelves();
  const { meta } = useListMeta();
  const { items: wishes } = useWishlist();
  const info = useListItems(shelves.flatMap((s) => s.productIds));
  const [naming, setNaming] = useState(false);

  if (store.status === "loading") return <Skeleton className="h-96 w-full rounded-3xl" />;
  if (store.status === "error") return <ErrorState message={store.error} />;

  const newList = async (name: string) => {
    const list = await create(name);
    window.setTimeout(() => router.push(`/lists/${encodeURIComponent(list.id)}`), 150);
  };

  return (
    <div className="animate-fade-in space-y-7">
      <div className="flex items-baseline justify-between gap-3">
        <div>
          <h1 className="font-display text-[40px] leading-none">Lists</h1>
          <p className="mt-2 text-[14px] text-muted">Favorites, want lists and cards to&nbsp;sell</p>
        </div>
        {shelves.length > 0 && (
          <button type="button" onClick={() => setNaming(true)} className="inline-flex h-9 items-center gap-1.5 rounded-full bg-lime px-3.5 text-[14px] font-semibold text-[#0b0b0c] active:scale-[0.97]">
            <Plus className="size-4" strokeWidth={2.5} /> New
          </button>
        )}
      </div>

      {error && <p className="text-[13px] text-down">{error}</p>}

      {shelves.length === 0 ? (
        <div className="flex flex-col items-center pt-2 text-center">
          <div className="flex h-[150px] w-full items-center justify-center rounded-[20px] border border-border bg-image-well">
            <ListPlaceholderFan cardWidth={66} />
          </div>
          <h2 className="font-display mt-7 text-[26px]">No lists yet</h2>
          <p className="mt-2.5 max-w-[300px] text-balance text-[15px] text-muted">Group your favorite illustration rares, a want list, or the cards you&apos;re taking to a show. Share any list as a link.</p>
          <button type="button" onClick={() => setNaming(true)} className="mt-6 inline-flex h-[50px] items-center gap-1.5 rounded-full bg-lime px-[22px] text-[16px] font-semibold text-[#0b0b0c] active:scale-[0.97]">
            <Plus className="size-4" strokeWidth={2.5} /> Create a list
          </button>
        </div>
      ) : (
        <div className="grid grid-cols-2 gap-3 md:grid-cols-3">
          {shelves.map((list) => (
            <ListTile key={list.id} list={list} items={list.productIds.map(info)} forSale={meta(list.id).forSale === true} />
          ))}
        </div>
      )}

      <TrackingPanel watchCount={store.data.watchlist.length} wishCount={wishes.length} />

      <ListNameDialog open={naming} onOpenChange={setNaming} title="New list" action="Create list" onSave={newList} />
    </div>
  );
}
