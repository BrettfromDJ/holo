"use client";
/* eslint-disable @next/next/no-img-element -- set logos come from the pricing source's CDN */

import { useHeroLink } from "@/lib/motion/hero";
import { Check } from "lucide-react";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { HoloTilt, isFoilCard } from "@/components/motion/holo-tilt";
import { ProductImage } from "@/components/product/product-image";
import { WishHeart } from "@/components/wishlist/wish-items";
import { categoryOf } from "@/lib/catalog";
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
        <span className="truncate font-display text-[20px] uppercase leading-none tracking-[0.01em]">{game.name}</span>
        <span className="tabular shrink-0 text-[12px] text-subtle">
          {game.sets} set{game.sets === 1 ? "" : "s"}{game.cardCount ? ` · ${compactCount(game.cardCount)} cards` : ""}
        </span>
      </div>
    </Link>
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
            <img src={set.iconUrl} alt="" loading="lazy" className="h-full w-full rounded-lg object-cover shadow-lg shadow-black/40 transition-transform duration-500 ease-[var(--ease-apple)] group-hover:scale-[1.03]" />
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
          {[set.releaseDate ? formatDate(set.releaseDate) : null, set.loaded ? `${set.productCount ?? 0} products` : "Loading soon"].filter(Boolean).join(" · ")}
        </p>
      </div>
    </>
  );
  const cls = "group flex flex-col overflow-hidden rounded-[var(--radius-card)] border border-border bg-surface";
  return set.loaded ? (
    <Link href={`/explore/${encodeURIComponent(set.slug)}`} className={cn(cls, "transition-colors hover:border-border-strong")}>
      {body}
    </Link>
  ) : (
    <div className={cn(cls, "opacity-45")} title="This set loads in an upcoming daily catalog sync.">
      {body}
    </div>
  );
}

let exploreIndex: Promise<{ games: ExploreGame[]; sets: ExploreSet[] }> | null = null;

/** Brands and sets from /api/explore, fetched once per page load. */
export function useExploreIndex() {
  const [state, setState] = useState<{ status: "loading" } | { status: "error"; message: string } | { status: "ready"; games: ExploreGame[]; sets: ExploreSet[] }>({ status: "loading" });
  useEffect(() => {
    exploreIndex ??= fetch("/api/explore").then(async (res) => {
      const body = await res.json().catch(() => null);
      if (!res.ok) throw new Error(body?.error?.message ?? "Couldn't load the catalog.");
      return { games: body.games ?? [], sets: body.sets ?? [] };
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
export function ProductTile({ item, owned, gameSlug, showBrand }: { item: ExploreProduct; owned: boolean; gameSlug?: string | null; showBrand?: boolean }) {
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
          <span className="absolute left-2 top-2 flex items-center gap-1 rounded-full bg-background/85 px-2 py-0.5 text-[11px] font-medium backdrop-blur">
            <Check className="size-3" /> Owned
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
