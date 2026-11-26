"use client";

import { ChevronRight, Eye, Heart, Plus } from "lucide-react";
import Link from "next/link";
import { ProductImage } from "@/components/product/product-image";
import { money } from "@/lib/format";
import type { Shelf } from "@/lib/store/shelves";
import { listTotals, type ListItemInfo } from "./use-lists";

/** Three soft card shapes fanned around a lime plus: an empty list, waiting for cards (the app's `ListPlaceholderFan`). */
export function ListPlaceholderFan({ cardWidth = 54 }: { cardWidth?: number }) {
  const h = (cardWidth * 74) / 54;
  return (
    <div className="relative flex items-center justify-center" style={{ height: h + 16 }} aria-hidden>
      {[0, 1, 2].map((i) => (
        <span
          key={i}
          className="absolute border border-border-strong bg-image-well"
          style={{
            width: cardWidth,
            height: h,
            borderRadius: cardWidth / 9,
            transform: `translateX(${(i - 1) * cardWidth * 0.52}px) rotate(${(i - 1) * 10}deg)`,
            zIndex: i === 1 ? 1 : 0,
            backgroundImage: `linear-gradient(rgb(255 255 255 / ${i === 1 ? 0.07 : 0.045}), rgb(255 255 255 / ${i === 1 ? 0.07 : 0.045}))`,
          }}
        />
      ))}
      <span className="relative z-[2] flex items-center justify-center rounded-full border border-lime/40 bg-image-well text-lime" style={{ width: cardWidth * 0.67, height: cardWidth * 0.67 }}>
        <Plus style={{ width: cardWidth / 3, height: cardWidth / 3 }} strokeWidth={2.5} />
      </span>
    </div>
  );
}

/** A list on the Lists page: its top cards fanned in a dark well, then its name, count and worth. */
export function ListTile({ list, items, forSale }: { list: Shelf; items: ListItemInfo[]; forSale: boolean }) {
  const { market } = listTotals(items, {});
  const shown = items
    .filter((i) => i.product)
    .sort((a, b) => (b.market ?? 0) - (a.market ?? 0))
    .slice(0, 3);
  const mid = (shown.length - 1) / 2;
  const count = list.productIds.length;
  return (
    <Link href={`/lists/${encodeURIComponent(list.id)}`} className="lists-glass group flex flex-col gap-3 rounded-[20px] p-2 transition-transform active:scale-[0.98]">
      <div className="relative flex h-28 items-center justify-center overflow-hidden rounded-[14px] bg-image-well">
        {shown.length === 0 ? (
          <ListPlaceholderFan />
        ) : (
          shown.map((info, i) => (
            <div
              key={info.productId}
              className="absolute h-20 w-[58px] drop-shadow-[0_3px_6px_rgb(0_0_0/0.5)] transition-transform duration-300 group-hover:-translate-y-0.5"
              style={{ transform: `translate(${(i - mid) * 30}px, -2px) rotate(${(i - mid) * 10}deg)`, transformOrigin: "bottom center", zIndex: 10 - Math.abs(i - mid) }}
            >
              <ProductImage product={info.product} size="xs" className="h-full w-full" />
            </div>
          ))
        )}
        {forSale && <span className="absolute left-2 top-2 rounded-full bg-lime px-[7px] py-[3px] text-[10px] font-semibold text-[#0b0b0c]">For sale</span>}
      </div>
      <div className="px-1 pb-1">
        <p className="truncate text-[15px] font-semibold">{list.name}</p>
        <p className="tabular truncate text-[12px] text-muted">{count === 0 ? "Empty · tap to add" : `${count} card${count === 1 ? "" : "s"} · ${money(market)}`}</p>
      </div>
    </Link>
  );
}

/** The Tracking panel's rows: Watchlist and Wishlist. */
export function TrackingPanel({ watchCount, wishCount }: { watchCount: number; wishCount: number }) {
  const row = (href: string, title: string, sub: string, Icon: typeof Eye, count: number) => (
    <Link href={href} className="flex items-center gap-3 py-3">
      <span className="flex size-9 items-center justify-center rounded-full bg-lime/[0.12] text-lime">
        <Icon className="size-[15px]" strokeWidth={2.5} />
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-[15px] font-semibold">{title}</span>
        <span className="block text-[12px] text-muted">{sub}</span>
      </span>
      <span className={count === 0 ? "tabular text-[15px] font-semibold text-muted" : "tabular text-[15px] font-semibold"}>{count}</span>
      <ChevronRight className="size-4 text-subtle" />
    </Link>
  );
  return (
    <section>
      <h2 className="font-display mb-3 text-[22px]">Tracking</h2>
      <div className="rounded-[18px] border border-border bg-surface px-3.5">
        {row("/watchlist", "Watchlist", "Prices you're watching", Eye, watchCount)}
        <div className="ml-12 h-px bg-border" />
        {row("/wishlist", "Wishlist", "Cards you want next", Heart, wishCount)}
      </div>
    </section>
  );
}
