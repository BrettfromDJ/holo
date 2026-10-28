"use client";
/* eslint-disable @next/next/no-img-element -- set logos come from the pricing source's CDN */

import { FlipGrid, FlipItem } from "@/components/motion/flip-grid";
import { ChevronLeft } from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { ProductTile, useOwnedIds } from "@/components/explore/explore-items";
import { Segmented } from "@/components/ui/segmented";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { compareCollectorNumbers } from "@/lib/collector-number";
import { packCount, pricePerPack } from "@/lib/packs";
import type { ExploreProduct, ExploreSet } from "@/lib/explore/types";
import { formatDate, money, relativeTime } from "@/lib/format";

type Tab = "single" | "sealed";
type Sort = "price" | "perPack" | "number" | "name";

export default function ExploreSetPage() {
  const { slug } = useParams<{ slug: string }>();
  const [state, setState] = useState<{ set: ExploreSet; products: ExploreProduct[] } | { error: string } | null>(null);
  const [tab, setTab] = useState<Tab>("single");
  const [sortChoice, setSort] = useState<Sort>("price");
  const owned = useOwnedIds();

  useEffect(() => {
    fetch(`/api/explore/sets/${encodeURIComponent(slug)}`)
      .then(async (res) => {
        const body = await res.json().catch(() => null);
        if (!res.ok) throw new Error(body?.error?.message ?? "Couldn't load this set.");
        return body as { set: ExploreSet; products: ExploreProduct[] };
      })
      .then(
        (b) => {
          setState(b);
          // Open on whichever tab has products.
          if (!b.products.some((p) => p.product.kind === "single")) setTab("sealed");
        },
        (e: Error) => setState({ error: e.message }),
      );
  }, [slug]);

  const products = useMemo(() => (state && "products" in state ? state.products : []), [state]);
  const counts = useMemo(() => ({ single: products.filter((p) => p.product.kind === "single").length, sealed: products.filter((p) => p.product.kind === "sealed").length }), [products]);
  const gameSlug = state && "set" in state ? state.set.gameSlug : null;
  // Price per pack only applies to sealed products.
  const sort: Sort = tab === "single" && sortChoice === "perPack" ? "price" : sortChoice;
  const list = useMemo(() => {
    const l = products.filter((p) => p.product.kind === tab);
    if (sort === "price") return l.sort((a, b) => (b.market ?? -1) - (a.market ?? -1));
    if (sort === "perPack") {
      const per = (p: ExploreProduct) => pricePerPack(p.market, packCount(p.product, gameSlug)) ?? Infinity;
      return l.sort((a, b) => per(a) - per(b));
    }
    if (sort === "number") return l.sort((a, b) => compareCollectorNumbers(a.product.number, b.product.number));
    return l.sort((a, b) => a.product.name.localeCompare(b.product.name));
  }, [products, tab, sort, gameSlug]);
  const value = list.reduce((s, p) => s + (p.market ?? 0), 0);
  const ownedHere = products.filter((p) => owned.has(p.product.id)).length;

  return (
    <div className="animate-fade-in">
      {state && "set" in state ? (
        <Link href={`/explore/g/${encodeURIComponent(state.set.gameSlug)}`} className="mb-6 inline-flex items-center gap-1 text-[13px] text-muted hover:text-foreground">
          <ChevronLeft className="size-4" /> {state.set.gameName}
        </Link>
      ) : (
        <Link href="/explore" className="mb-6 inline-flex items-center gap-1 text-[13px] text-muted hover:text-foreground">
          <ChevronLeft className="size-4" /> Explore
        </Link>
      )}

      {!state ? (
        <>
          <Skeleton className="h-24 w-full rounded-3xl" />
          <div className="mt-8 grid grid-cols-2 gap-5 sm:grid-cols-3 lg:grid-cols-4">
            {Array.from({ length: 8 }).map((_, i) => (
              <Skeleton key={i} className="aspect-[5/7] rounded-2xl" />
            ))}
          </div>
        </>
      ) : "error" in state ? (
        <p className="py-20 text-center text-[14px] text-muted">{state.error}</p>
      ) : (
        <>
          <header className="flex flex-col gap-5 sm:flex-row sm:items-center">
            {state.set.iconUrl ? (
              <img src={state.set.iconUrl} alt="" className="aspect-[3/2] w-full max-w-sm shrink-0 rounded-2xl object-cover shadow-xl shadow-black/40 sm:w-56" />
            ) : state.set.imageUrl ? (
              <div className="flex h-28 w-full shrink-0 items-center justify-center rounded-2xl bg-image-well p-3 sm:w-40">
                <img src={state.set.imageUrl} alt="" className="max-h-full max-w-full object-contain" />
              </div>
            ) : null}
            <div className="min-w-0">
              <p className="text-[12px] font-medium font-mono uppercase tracking-[0.06em] text-subtle">{state.set.gameName}</p>
              <h1 className="mt-1 text-[28px] font-semibold leading-tight tracking-[-0.02em]">{state.set.name}</h1>
              <p className="tabular mt-1 text-[13px] text-muted">
                {[
                  state.set.releaseDate && `Released ${formatDate(state.set.releaseDate)}`,
                  `${products.length} products`,
                  ownedHere ? `${ownedHere} owned` : null,
                  state.set.syncedAt && `prices from ${relativeTime(state.set.syncedAt)}`,
                ]
                  .filter(Boolean)
                  .join(" · ")}
              </p>
            </div>
          </header>

          <div className="sticky top-[calc(3.5rem+env(safe-area-inset-top))] z-20 -mx-4 mt-6 flex flex-wrap items-center justify-between gap-3 bg-background/90 px-4 py-3 backdrop-blur-xl sm:-mx-8 sm:px-8 lg:top-0">
            <Segmented
              ariaLabel="Product type"
              value={tab}
              onChange={setTab}
              options={[
                { value: "single", label: `Singles · ${counts.single}` },
                { value: "sealed", label: `Sealed · ${counts.sealed}` },
              ]}
            />
            <div className="flex items-center gap-3">
              <span className="tabular hidden text-[12px] text-subtle sm:inline">Set value {money(value)}</span>
              <Select value={sort} onValueChange={(v) => setSort(v as Sort)}>
                <SelectTrigger aria-label="Sort" className="h-9 w-[196px]">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="price">Price: high to low</SelectItem>
                  {tab === "sealed" && <SelectItem value="perPack">Price per pack: low to high</SelectItem>}
                  <SelectItem value="number">Collector number</SelectItem>
                  <SelectItem value="name">Name</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>

          {list.length ? (
            <FlipGrid className="mt-4 grid grid-cols-2 gap-x-5 gap-y-10 sm:grid-cols-3 lg:grid-cols-4">
              {list.map((item, i) => (
                <FlipItem key={item.product.id} flipKey={item.product.id} index={i}>
                  <ProductTile item={item} owned={owned.has(item.product.id)} gameSlug={gameSlug} />
                </FlipItem>
              ))}
            </FlipGrid>
          ) : (
            <p className="py-20 text-center text-[14px] text-muted">No {tab === "single" ? "singles" : "sealed products"} in this set.</p>
          )}
        </>
      )}
    </div>
  );
}
