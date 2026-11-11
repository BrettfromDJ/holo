"use client";
/* eslint-disable @next/next/no-img-element -- set logos come from the pricing source's CDN */

import { useHeroLink } from "@/lib/motion/hero";
import { Check, Layers } from "lucide-react";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { HoloTilt, isFoilCard } from "@/components/motion/holo-tilt";
import { ProductImage } from "@/components/product/product-image";
import { WishHeart } from "@/components/wishlist/wish-items";
import { categoryOf } from "@/lib/catalog";
import type { ExploreMarket } from "@/lib/explore/movers";
import type { ExploreGame, ExploreProduct, ExploreSet } from "@/lib/explore/types";
import { formatDate, money } from "@/lib/format";
import { packCount, pricePerPack } from "@/lib/packs";
import { usePortfolio } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";

/** Product ids the user owns, for "Owned" badges. */
export function useOwnedIds() {
  // Owned anywhere in the collection, whichever portfolio is shown.
  const { holdings } = usePortfolio({ ignoreFilter: true });
  return useMemo(() => new Set(holdings.map((h) => h.identity.productId)), [holdings]);
}

/** How many of each product the user holds, across every copy (raw and graded), for "Owned ×N". */
export function useOwnedQuantities() {
  const { holdings } = usePortfolio({ ignoreFilter: true });
  return useMemo(() => {
    const qty = new Map<string, number>();
    for (const h of holdings) qty.set(h.identity.productId, (qty.get(h.identity.productId) ?? 0) + h.quantity);
    return qty;
  }, [holdings]);
}

/** "Owned", or "Owned ×3" when there's more than one. */
export function ownedLabel(quantity: number | undefined): string {
  const n = Math.round(quantity ?? 0);
  return n > 1 ? `Owned ×${n}` : "Owned";
}

function isNew(releaseDate: string | null) {
  if (!releaseDate) return false;
  const age = Date.now() - Date.parse(releaseDate);
  return age < 60 * 24 * 60 * 60 * 1000;
}

function compactCount(n: number) {
  return n >= 1000 ? `${(n / 1000).toFixed(n >= 10_000 ? 0 : 1)}K` : String(n);
}

/** Logos drawn in black, which vanish on the dark theme: shown white there instead. */
export function logoTone(game: Pick<ExploreGame, "slug" | "name">) {
  return /one[\s-]?piece/i.test(`${game.slug} ${game.name}`) ? "dark:brightness-0 dark:invert" : "";
}

/** A brand (Pokémon, Pokémon Japan, Lorcana…) with its logo. */
export function GameTile({ game }: { game: ExploreGame }) {
  return (
    <Link href={`/explore/g/${encodeURIComponent(game.slug)}`} className="tint tint-borderless hype-surface tint-lime group flex flex-col overflow-hidden rounded-[var(--radius-card)] transition-transform duration-300 hover:-translate-y-1">
      <div className="flex aspect-[16/9] items-center justify-center p-6 sm:p-8">
        {game.logoUrl ? (
          <img src={game.logoUrl} alt="" loading="lazy" className={cn("max-h-full max-w-full object-contain drop-shadow-[0_8px_18px_rgba(0,0,0,0.5)] transition-transform duration-500 ease-[var(--ease-apple)] group-hover:scale-105", logoTone(game))} />
        ) : (
          <span className="text-center text-[22px] font-semibold tracking-tight text-foreground/80">{game.name}</span>
        )}
      </div>
      <div className="flex items-center justify-between gap-3 border-t border-border px-4 py-3">
        <span className="truncate font-display text-[16px] leading-none ">{game.name}</span>
        <span className="tabular shrink-0 text-[12px] text-subtle">
          {game.sets} set{game.sets === 1 ? "" : "s"}{game.cardCount ? ` · ${compactCount(game.cardCount)} cards` : ""}
        </span>
      </div>
    </Link>
  );
}

/**
 * A set's banner art filling its frame (the app's SetArt): the banner cropped to fill, else a
 * sample product fitted inside, else just a mark (the name is shown beside it). The parent sizes it.
 */
/** Our own set logo, centred over the set's background art (English Pokémon sets). */
export function SetLogo({ url, className }: { url: string | null | undefined; className?: string }) {
  if (!url) return null;
  return (
    <img
      src={url}
      alt=""
      loading="lazy"
      className={cn("pointer-events-none absolute inset-0 m-auto max-h-[62%] max-w-[74%] object-contain drop-shadow-[0_6px_14px_rgba(0,0,0,0.55)]", className)}
    />
  );
}

export function SetArt({ set, className }: { set: Pick<ExploreSet, "iconUrl" | "imageUrl" | "logoUrl">; className?: string }) {
  return (
    <div className={cn("relative flex items-center justify-center overflow-hidden bg-image-well", className)}>
      {set.iconUrl ? (
        <>
          <img src={set.iconUrl} alt="" loading="lazy" className="absolute inset-0 h-full w-full object-cover transition-transform duration-500 ease-[var(--ease-apple)] group-hover:scale-[1.03]" />
          <SetLogo url={set.logoUrl} />
        </>
      ) : set.imageUrl ? (
        <img src={set.imageUrl} alt="" loading="lazy" className="absolute inset-3 h-[calc(100%-1.5rem)] w-[calc(100%-1.5rem)] object-contain transition-transform duration-500 ease-[var(--ease-apple)] group-hover:scale-[1.03]" />
      ) : (
        <Layers className="size-6 text-lime/60" strokeWidth={1.5} />
      )}
    </div>
  );
}

/** A set with its banner art, release date and size. */
export function SetTile({ set }: { set: ExploreSet }) {
  const body = (
    <>
      {/* Fixed 3:2 frame. TCG API's set_icon_url is the set's banner art; image_url is a sample product. */}
      <div className="relative aspect-[3/2] overflow-hidden">
        <div className="absolute inset-4 flex items-center justify-center sm:inset-5">
          {set.iconUrl ? (
            <div className="relative h-full w-full transition-transform duration-500 ease-[var(--ease-apple)] group-hover:scale-[1.03]">
              <img src={set.iconUrl} alt="" loading="lazy" className="h-full w-full rounded-lg object-cover shadow-lg shadow-black/40" />
              <SetLogo url={set.logoUrl} />
            </div>
          ) : set.imageUrl ? (
            <img src={set.imageUrl} alt="" loading="lazy" className="h-full w-full object-contain drop-shadow-[0_8px_16px_rgba(0,0,0,0.45)] transition-transform duration-500 ease-[var(--ease-apple)] group-hover:scale-[1.03]" />
          ) : (
            <span className="text-center text-[13px] font-semibold text-subtle">{set.name}</span>
          )}
        </div>
      </div>
      <div className="border-t border-border px-4 py-3">
        <p className="flex items-start gap-2">
          <span className="line-clamp-2 text-[14px] font-medium leading-snug">{set.name}</span>
          {isNew(set.releaseDate) && <span className="mt-px shrink-0 rounded bg-[var(--cat-1)]/20 px-1.5 py-px text-[10px] font-medium font-mono uppercase tracking-[0.06em] text-[var(--cat-1)]">New</span>}
        </p>
        <p className="tabular mt-0.5 truncate text-[12px] text-subtle">
          {[set.releaseDate ? formatDate(set.releaseDate) : null, set.loaded ? `${set.productCount ?? 0} products` : null].filter(Boolean).join(" · ")}
        </p>
      </div>
    </>
  );
  // Every set opens; one whose cards aren't in the catalog yet says so on its page.
  return (
    <Link
      href={`/explore/${encodeURIComponent(set.slug)}`}
      className="group flex flex-col overflow-hidden rounded-[var(--radius-card)] border border-border bg-surface transition-colors hover:border-border-strong"
    >
      {body}
    </Link>
  );
}

type ExploreIndexData = { games: ExploreGame[]; sets: ExploreSet[] } & ExploreMarket;
let exploreIndex: Promise<ExploreIndexData> | null = null;

/** Brands and sets from /api/explore, fetched once per page load. */
export function useExploreIndex() {
  const [state, setState] = useState<{ status: "loading" } | { status: "error"; message: string } | ({ status: "ready" } & ExploreIndexData)>({ status: "loading" });
  useEffect(() => {
    exploreIndex ??= fetch("/api/explore").then(async (res) => {
      const body = await res.json().catch(() => null);
      if (!res.ok) throw new Error(body?.error?.message ?? "Couldn't load the catalog.");
      return { games: body.games ?? [], sets: body.sets ?? [], trending: body.trending ?? [], drops: body.drops ?? [], hotSealed: body.hotSealed ?? [], boosterBoxes: body.boosterBoxes ?? [] };
    });
    exploreIndex.then(
      (d) => setState({ status: "ready", ...d }),
      (e: Error) => {
        exploreIndex = null;
        setState({ status: "error", message: e.message });
      },
    );
  }, []);
  return state;
}

/** A catalog product; opens its full product page (served from the stored catalog). */
export function ProductTile({ item, owned, ownedQty, gameSlug, showBrand }: { item: ExploreProduct; owned: boolean; ownedQty?: number; gameSlug?: string | null; showBrand?: boolean }) {
  const hero = useHeroLink();
  const p = item.product;
  const perPack = pricePerPack(item.market, packCount(p, gameSlug));
  // Open the page on the printing this tile shows.
  const href = `/product/${encodeURIComponent(p.id)}${item.printing ? `?printing=${encodeURIComponent(item.printing)}` : ""}`;
  return (
    <Link href={href} onClick={(e) => hero(e, href)} className="group flex w-full min-w-0 flex-col text-left">
      <div className="relative">
        {/* Tall, card-shaped tiles so cards fill the width; sealed sits in the same frame. */}
        {p.kind === "single" && p.imageUrl ? (
          <div className="flex aspect-[5/7] w-full items-end justify-center">
            <HoloTilt max={8} foil={isFoilCard(p)} radius="4.5% / 3.2%" className="aspect-[63/88] h-full max-w-full">
              <ProductImage product={p} size="lg" frame={false} className="h-full w-full" />
            </HoloTilt>
          </div>
        ) : (
          <ProductImage product={p} size="lg" className="aspect-[5/7] w-full items-end transition-transform duration-500 ease-[var(--ease-apple)] group-hover:-translate-y-1" />
        )}
        <WishHeart product={p} price={item.market} printing={item.printing} className="absolute right-2 top-2" />
        {owned && (
          <span className="tabular absolute left-2 top-2 flex items-center gap-1 rounded-full bg-background/85 px-2 py-0.5 text-[11px] font-medium text-up backdrop-blur">
            <Check className="size-3" /> {ownedLabel(ownedQty)}
          </span>
        )}
      </div>
      {showBrand && item.gameName && <p className="mt-2.5 truncate text-[10px] font-medium font-mono uppercase tracking-[0.06em] text-subtle">{item.gameName}</p>}
      <p className={cn("line-clamp-2 text-[13px] font-medium leading-snug", showBrand && item.gameName ? "mt-0.5" : "mt-2.5")}>{p.name}</p>
      <p className="truncate text-[12px] text-muted">{[p.number && `#${p.number}`, p.rarity ?? (p.kind === "sealed" ? categoryOf(p) : null)].filter(Boolean).join(" · ")}</p>
      <p className="hype-num tabular mt-1.5 text-[19px] leading-none">
        {item.market === null ? <span className="text-subtle">No price</span> : money(item.market)}
        {perPack !== null && <span className="ml-1.5 text-[12px] font-normal text-muted">{money(perPack)}/pack</span>}
      </p>
    </Link>
  );
}
