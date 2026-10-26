"use client";
/* eslint-disable @next/next/no-img-element -- set logos come from the pricing source's CDN */

import { Check, ExternalLink, Eye, Plus } from "lucide-react";
import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { ProductImage } from "@/components/product/product-image";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { categoryOf } from "@/lib/catalog";
import type { ExploreGame, ExploreProduct, ExploreSet } from "@/lib/explore/types";
import { formatDate, money, relativeTime } from "@/lib/format";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";

/** Product ids the user owns, for "Owned" badges. */
export function useOwnedIds() {
  const { holdings } = usePortfolio();
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

/** A brand (Pokémon, Pokémon Japan, Lorcana…) with its logo. */
export function GameTile({ game }: { game: ExploreGame }) {
  return (
    <Link href={`/explore/g/${encodeURIComponent(game.slug)}`} className="group flex flex-col overflow-hidden rounded-[var(--radius-card)] border border-border bg-surface transition-colors hover:border-border-strong">
      <div className="flex aspect-[16/9] items-center justify-center p-6 sm:p-8">
        {game.logoUrl ? (
          <img src={game.logoUrl} alt="" loading="lazy" className="max-h-full max-w-full object-contain drop-shadow-[0_8px_18px_rgba(0,0,0,0.5)] transition-transform duration-500 ease-[var(--ease-apple)] group-hover:scale-105" />
        ) : (
          <span className="text-center text-[22px] font-semibold tracking-tight text-foreground/80">{game.name}</span>
        )}
      </div>
      <div className="flex items-center justify-between gap-3 border-t border-border px-4 py-3">
        <span className="truncate text-[14px] font-medium">{game.name}</span>
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
          {isNew(set.releaseDate) && <span className="mt-px shrink-0 rounded bg-[var(--cat-1)]/20 px-1.5 py-px text-[10px] font-semibold uppercase tracking-wider text-[var(--cat-1)]">New</span>}
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

export function ProductTile({ item, owned, onOpen }: { item: ExploreProduct; owned: boolean; onOpen: () => void }) {
  const p = item.product;
  return (
    <button onClick={onOpen} className="group flex w-full min-w-0 flex-col text-left">
      <div className="relative">
        <ProductImage product={p} className="aspect-square w-full transition-transform duration-500 ease-[var(--ease-apple)] group-hover:-translate-y-1" />
        {owned && (
          <span className="absolute left-2 top-2 flex items-center gap-1 rounded-full bg-background/85 px-2 py-0.5 text-[11px] font-medium backdrop-blur">
            <Check className="size-3" /> Owned
          </span>
        )}
      </div>
      <p className="mt-2.5 line-clamp-2 text-[13px] font-medium leading-snug">{p.name}</p>
      <p className="truncate text-[12px] text-muted">{[p.number && `#${p.number}`, p.rarity ?? (p.kind === "sealed" ? categoryOf(p) : null)].filter(Boolean).join(" · ")}</p>
      <p className="tabular mt-1 text-[14px] font-semibold">{item.market === null ? <span className="text-subtle">No price</span> : money(item.market)}</p>
    </button>
  );
}

/** Detail sheet for a catalog product — everything comes from the stored catalog. */
export function ProductSheet({ item, onClose }: { item: ExploreProduct | null; onClose: () => void }) {
  const { openAdd } = useStore();
  const owned = useOwnedIds();
  // Keep showing the last product while the sheet animates closed.
  const last = useRef<ExploreProduct | null>(null);
  if (item) last.current = item;
  const shown = item ?? last.current;
  if (!shown) return null;
  const p = shown.product;
  const hit = { product: p, printing: shown.printing, market: shown.market, priceUpdatedAt: shown.priceUpdatedAt };

  return (
    <Dialog open={Boolean(item)} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-[640px]">
        <div className="grid gap-6 overflow-y-auto p-6 sm:grid-cols-[220px_1fr]">
          <ProductImage product={p} size="lg" className={cn("mx-auto w-full max-w-[220px]", p.kind === "single" ? "aspect-[63/88]" : "aspect-square")} />
          <div className="min-w-0">
            <div className="flex flex-wrap gap-1.5">
              <Badge variant="outline">{categoryOf(p)}</Badge>
              {p.rarity && <Badge variant="outline">{p.rarity}</Badge>}
              {owned.has(p.id) && <Badge>Owned</Badge>}
            </div>
            <DialogTitle className="mt-3 text-[20px] leading-tight">{p.name}</DialogTitle>
            <DialogDescription className="mt-1">{[p.setName, p.number && `#${p.number}`, shown.printing].filter(Boolean).join(" · ")}</DialogDescription>
            <p className="tabular mt-5 text-[32px] font-semibold leading-none tracking-[-0.03em]">{shown.market === null ? <span className="text-[18px] text-subtle">No market price</span> : money(shown.market)}</p>
            <p className="mt-1.5 text-[12px] text-subtle">Market price · {shown.priceUpdatedAt ? `updated ${relativeTime(shown.priceUpdatedAt)}` : "from the stored catalog"}</p>
            <div className="mt-6 flex flex-wrap gap-2">
              <Button
                variant="primary"
                onClick={() => {
                  onClose();
                  openAdd({ hit });
                }}
              >
                <Plus /> Add to collection
              </Button>
              <Button
                variant="secondary"
                onClick={() => {
                  onClose();
                  openAdd({ hit, watch: true });
                }}
              >
                <Eye /> Watch
              </Button>
              {p.tcgplayerUrl && (
                <Button variant="ghost" asChild>
                  <a href={p.tcgplayerUrl} target="_blank" rel="noreferrer">
                    TCGplayer <ExternalLink />
                  </a>
                </Button>
              )}
            </div>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
