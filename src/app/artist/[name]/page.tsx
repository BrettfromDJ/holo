"use client";
/* eslint-disable @next/next/no-img-element -- card art comes from the catalog's CDN */

import Link from "next/link";
import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { ProductImage } from "@/components/product/product-image";
import { withEditionArt } from "@/lib/editions";
import type { ExploreProduct } from "@/lib/explore/types";
import { money } from "@/lib/format";
import { rememberViewed } from "@/lib/search-history";

/**
 * One artist's page: every card they drew, priciest first, under their top card's art blurred.
 * Same as the app's `ArtistPage`: three columns of simple tiles (art, name, set, price).
 */
export default function ArtistPage() {
  const { name: raw } = useParams<{ name: string }>();
  const name = decodeURIComponent(raw);
  const [cards, setCards] = useState<ExploreProduct[] | null>(null);

  useEffect(() => {
    fetch(`/api/artists/${encodeURIComponent(name)}`)
      .then((r) => r.json())
      .then((b: { cards?: ExploreProduct[] }) => setCards(b.cards ?? []), () => setCards([]));
  }, [name]);

  const backdrop = cards?.[0] ? withEditionArt(cards[0].product, cards[0].printing).imageUrl : null;

  return (
    <div className="relative isolate animate-fade-in">
      {backdrop && (
        <div
          aria-hidden
          className="pointer-events-none absolute -inset-x-4 -top-6 -z-10 h-[480px] overflow-hidden sm:-inset-x-8"
          style={{ maskImage: "linear-gradient(to bottom, black, black 42%, transparent 92%)", WebkitMaskImage: "linear-gradient(to bottom, black, black 42%, transparent 92%)" }}
        >
          <img src={backdrop} alt="" className="h-full w-full scale-125 object-cover blur-[40px] brightness-75" />
          <div className="absolute inset-0 bg-black/25" />
        </div>
      )}
      <p className="font-mono text-[11px] uppercase tracking-[0.08em] text-muted">Illustrator</p>
      <h1 className="mt-2 font-display text-[34px] leading-[1.02] tracking-[-0.035em] text-balance sm:text-[44px]">{name}</h1>
      {cards && <p className="tabular mt-2.5 font-mono text-[11px] text-subtle">{cards.length === 1 ? "1 card" : `${cards.length} cards`}</p>}
      {!cards ? (
        <div className="mt-5 grid grid-cols-3 gap-x-3 gap-y-[18px] sm:grid-cols-4 lg:grid-cols-6" aria-hidden>
          {Array.from({ length: 9 }, (_, i) => (
            <div key={i} className="aspect-[63/88] rounded-[5px] bg-white/[0.05]" />
          ))}
        </div>
      ) : cards.length === 0 ? (
        <p className="mt-5 text-[15px] text-muted">No cards found for this artist yet.</p>
      ) : (
        <div className="mt-5 grid grid-cols-3 gap-x-3 gap-y-[18px] sm:grid-cols-4 lg:grid-cols-6">
          {cards.map((item) => {
            const href = `/product/${encodeURIComponent(item.product.id)}${item.printing ? `?printing=${encodeURIComponent(item.printing)}` : ""}`;
            return (
              <Link key={item.product.id} href={href} onClick={() => rememberViewed(item)} className="group min-w-0">
                <ProductImage product={withEditionArt(item.product, item.printing)} size="md" frame={false} className="aspect-[63/88] w-full" />
                <p className="mt-1.5 truncate text-[12px] font-medium text-white">{item.product.name}</p>
                <p className="truncate text-[11px] text-muted">{item.product.setName ?? ""}</p>
                <p className="tabular mt-0.5 text-[13px] font-semibold text-white">{money(item.market)}</p>
              </Link>
            );
          })}
        </div>
      )}
    </div>
  );
}
