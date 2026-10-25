"use client";
/* eslint-disable @next/next/no-img-element -- set logos come from the pricing source's CDN */

import { Check, ExternalLink, Eye, Plus } from "lucide-react";
import Link from "next/link";
import { useMemo, useRef } from "react";
import { ProductImage } from "@/components/product/product-image";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { categoryOf } from "@/lib/catalog";
import type { ExploreProduct, ExploreSet } from "@/lib/explore/types";
import { formatDate, money, relativeTime } from "@/lib/format";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";

/** Product ids the user owns, for "Owned" badges. */
export function useOwnedIds() {
  const { holdings } = usePortfolio();
  return useMemo(() => new Set(holdings.map((h) => h.identity.productId)), [holdings]);
}

export function SetTile({ set }: { set: ExploreSet }) {
  const body = (
    <>
      <div className="flex aspect-[16/9] items-center justify-center rounded-2xl bg-image-well p-5">
        {set.imageUrl ? (
          <img src={set.imageUrl} alt="" loading="lazy" className="max-h-full max-w-full object-contain drop-shadow-[0_6px_14px_rgba(0,0,0,0.45)] transition-transform duration-500 group-hover:scale-105" />
        ) : set.iconUrl ? (
          <img src={set.iconUrl} alt="" loading="lazy" className="size-12 object-contain opacity-80" />
        ) : (
          <span className="text-center text-[13px] font-semibold text-subtle">{set.name}</span>
        )}
      </div>
      <p className="mt-3 truncate text-[14px] font-medium">{set.name}</p>
      <p className="truncate text-[12px] text-muted">
        {[set.releaseDate ? formatDate(set.releaseDate) : null, set.loaded ? `${set.productCount ?? 0} products` : "Loading soon"].filter(Boolean).join(" · ")}
      </p>
    </>
  );
  return set.loaded ? (
    <Link href={`/explore/${encodeURIComponent(set.slug)}`} className="group block">
      {body}
    </Link>
  ) : (
    <div className="block opacity-45" title="This set loads in an upcoming daily catalog sync.">
      {body}
    </div>
  );
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
