"use client";

import { ChevronLeft } from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { ProductTile, useOwnedIds } from "@/components/explore/explore-items";
import { Skeleton } from "@/components/ui/skeleton";
import type { ExploreProduct } from "@/lib/explore/types";

/** One artist's page: every card they drew, priciest first. Same as the app's `ArtistPage`. */
export default function ArtistPage() {
  const { name: raw } = useParams<{ name: string }>();
  const name = decodeURIComponent(raw);
  const [cards, setCards] = useState<ExploreProduct[] | null>(null);
  const owned = useOwnedIds();

  useEffect(() => {
    fetch(`/api/artists/${encodeURIComponent(name)}`)
      .then((r) => r.json())
      .then((b: { cards?: ExploreProduct[] }) => setCards(b.cards ?? []), () => setCards([]));
  }, [name]);

  return (
    <div className="mx-auto max-w-6xl px-4 pb-24 pt-6">
      <Link href="/explore" className="inline-flex items-center gap-1 text-[13px] text-muted hover:text-foreground">
        <ChevronLeft className="size-4" /> Explore
      </Link>
      <p className="mt-6 font-mono text-[11px] uppercase tracking-wider text-muted">Illustrator</p>
      <h1 className="mt-1 font-display text-[34px] leading-none tracking-tight sm:text-[44px]" style={{ textWrap: "balance" }}>{name}</h1>
      {cards && <p className="mt-2 text-[15px] text-muted">{cards.length === 1 ? "1 card" : `${cards.length} cards`}</p>}
      {!cards ? (
        <div className="mt-8 grid grid-cols-2 gap-5 sm:grid-cols-3 lg:grid-cols-4">
          {Array.from({ length: 8 }, (_, i) => <Skeleton key={i} className="aspect-[63/88] rounded-lg" />)}
        </div>
      ) : cards.length === 0 ? (
        <p className="mt-8 text-[15px] text-muted">No cards found for this artist yet.</p>
      ) : (
        <div className="mt-8 grid grid-cols-2 gap-x-5 gap-y-10 sm:grid-cols-3 lg:grid-cols-4">
          {cards.map((item) => <ProductTile key={item.product.id} item={item} owned={owned.has(item.product.id)} />)}
        </div>
      )}
    </div>
  );
}
