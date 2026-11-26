"use client";

import { useHeroLink } from "@/lib/motion/hero";
import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Delta, DeltaPill } from "@/components/product/delta";
import { PriceStatus } from "@/components/product/price-status";
import { HoloTilt, isFoilCard } from "@/components/motion/holo-tilt";
import { ProductImage } from "@/components/product/product-image";
import { categoryOf } from "@/lib/catalog";
import type { HoldingView } from "@/lib/finance/portfolio";
import { money } from "@/lib/format";
import { cn } from "@/lib/utils";
import { isStalePrice } from "@/lib/price-info";
import { MoreHorizontal } from "lucide-react";
import { cardHref } from "./collection-links";

/** A card's page, on the tapped copy's printing. */
export function holdingHref(h: HoldingView) {
  return cardHref(h);
}

export function holdingLabel(h: HoldingView): string | null {
  const parts: string[] = [];
  if (h.identity.grade) parts.push(`${h.identity.grade.company} ${h.identity.grade.grade}`);
  else if (h.identity.condition !== "Sealed" && h.identity.condition !== "Near Mint") parts.push(h.identity.condition);
  if (h.identity.printing && !["Normal", "Holofoil"].includes(h.identity.printing)) parts.push(h.identity.printing);
  return parts.length ? parts.join(" · ") : null;
}

/** A plain click that a handler can take over; modified clicks (new tab, etc.) keep the link. */
function plainClick(e: React.MouseEvent) {
  return !(e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey);
}

/** Per-unit price; "≈" marks a played copy estimated from Near Mint. */
export function unitPrice(h: HoldingView): string {
  return h.conditionEstimate && h.price !== null ? `≈ ${money(h.price)}` : money(h.price);
}

/** Compact row for dashboard sections. `metric` picks the right-hand figure. */
export function HoldingMiniRow({ h, metric = "gain", change }: { h: HoldingView; metric?: "gain" | "value" | "change" | "added"; change?: number | null }) {
  return (
    <Link href={holdingHref(h)} className="group -mx-2 flex items-center gap-3 rounded-xl px-2 py-2 transition-colors hover:bg-surface-2">
      <ProductImage product={h.product} grade={h.identity.grade} slabKey={h.key} size="xs" className="size-11 shrink-0 rounded-lg" />
      <div className="min-w-0 flex-1">
        <p className="truncate text-[14px] font-medium">{h.product?.name ?? "Unknown product"}</p>
        <p className="tabular truncate text-[12px] text-muted">
          {h.quantity} × {unitPrice(h)}
          {holdingLabel(h) && <span> · {holdingLabel(h)}</span>}
        </p>
      </div>
      <div className="shrink-0 text-right">
        <p className="tabular text-[14px] font-medium">{money(h.value)}</p>
        {metric === "change" ? (
          <DeltaPill ratio={change ?? null} className="mt-0.5" />
        ) : metric === "added" ? (
          <p className="tabular text-[12px] text-muted">{h.lastAcquired}</p>
        ) : (
          <Delta value={h.unrealized} ratio={h.unrealizedPct} className="text-[12px]" pctOnly={metric === "value"} />
        )}
      </div>
    </Link>
  );
}

/** Table-style row for the collection list view. */
/** `onOpen` opens your copy in place (Collection's sheet) instead of following the link. */
/** `onMore` adds a ⋯ at the end of the row opening its actions (the app's `RowMoreButton`). */
export function HoldingListRow({ h, onOpen, onMore }: { h: HoldingView; onOpen?: (h: HoldingView) => void; onMore?: (h: HoldingView) => void }) {
  const link = (
    <Link
      href={holdingHref(h)}
      onClick={(e) => {
        if (onOpen && plainClick(e)) {
          e.preventDefault();
          onOpen(h);
        }
      }}
      className="group grid grid-cols-[3rem_1fr_auto] items-center gap-4 px-4 py-3 transition-colors hover:bg-surface-2 md:grid-cols-[3.5rem_minmax(0,2.4fr)_repeat(5,minmax(0,1fr))]"
    >
      <ProductImage product={h.product} grade={h.identity.grade} slabKey={h.key} size="xs" className="size-12 rounded-lg md:size-14" />
      <div className="min-w-0">
        <p className="truncate text-[14px] font-medium">{h.product?.name ?? "Unknown product"}</p>
        <p className="mt-0.5 flex items-center gap-1.5 truncate text-[12px] text-muted">
          <span className="truncate">{[h.product?.setName, h.product ? categoryOf(h.product) : null].filter(Boolean).join(" · ")}</span>
          {holdingLabel(h) && (
            <Badge variant="outline" className="shrink-0">
              {holdingLabel(h)}
            </Badge>
          )}
        </p>
      </div>
      <div className="tabular hidden text-right text-[14px] md:block">{h.quantity}</div>
      <div className="tabular hidden text-right text-[14px] text-muted md:block">{money(h.avgCost)}</div>
      <div className="tabular hidden items-center justify-end gap-1.5 text-right text-[14px] md:flex">
        <PriceStatus holding={h} />
        {unitPrice(h)}
      </div>
      <div className="tabular hidden text-right text-[14px] font-medium md:block">{money(h.value)}</div>
      <div className="text-right">
        <p className="tabular text-[14px] font-medium md:hidden">{money(h.value)}</p>
        <Delta value={h.unrealized} className="block text-[13px] md:text-[14px]" />
        <Delta ratio={h.unrealizedPct} pctOnly className="block text-[12px]" />
      </div>
    </Link>
  );
  if (!onMore) return link;
  return (
    <div className="flex items-center">
      <div className="min-w-0 flex-1">{link}</div>
      <MoreButton onClick={() => onMore(h)} label={h.product?.name} className="mr-2" />
    </div>
  );
}

/** The ⋯ at the end of a row or on a tile: opens the same actions as the app's hold. */
export function MoreButton({ onClick, label, className }: { onClick: () => void; label?: string; className?: string }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={`More for ${label ?? "this card"}`}
      className={cn("flex size-9 shrink-0 items-center justify-center rounded-full text-muted transition-colors hover:bg-foreground/10 hover:text-foreground", className)}
    >
      <MoreHorizontal className="size-[18px]" />
    </button>
  );
}

export function HoldingListHeader({ className }: { className?: string }) {
  return (
    <div className={"hidden grid-cols-[3.5rem_minmax(0,2.4fr)_repeat(5,minmax(0,1fr))] gap-4 border-b border-border px-4 pb-3 text-[12px] font-medium text-subtle md:grid" + (className ? ` ${className}` : "")}>
      <span />
      <span>Product</span>
      <span className="text-right">Qty</span>
      <span className="text-right">Avg cost</span>
      <span className="text-right">Price</span>
      <span className="text-right">Value</span>
      <span className="text-right">Gain / loss</span>
    </div>
  );
}

/** Photo-forward card for the collection grid view. */
/** `onOpen` opens your copy in place (Collection's sheet) instead of following the link. */
export function HoldingTile({ h, onOpen, onMore }: { h: HoldingView; onOpen?: (h: HoldingView) => void; onMore?: (h: HoldingView) => void }) {
  const hero = useHeroLink();
  const shape = h.identity.grade ? "slab" : h.product?.kind === "single" && h.product.imageUrl ? "card" : "sealed";
  const link = (
    <Link
      href={holdingHref(h)}
      onClick={(e) => {
        if (onOpen && plainClick(e)) {
          e.preventDefault();
          onOpen(h);
        } else hero(e, holdingHref(h));
      }}
      className="group flex flex-col"
    >
      <div className="relative">
        {/* The tilt (and its glare) wraps the item's own shape, not the square tile around it. */}
        <div className="flex aspect-[5/7] w-full items-end justify-center">
          {shape === "sealed" ? (
            <HoloTilt max={8} foil={false} className="h-full w-full">
              <ProductImage product={h.product} className="h-full w-full" />
            </HoloTilt>
          ) : (
            <HoloTilt max={8} foil={shape === "card" && isFoilCard(h.product)} radius={shape === "slab" ? "7% / 4.4%" : "4.5% / 3.2%"} className={cn("h-full", shape === "slab" ? "aspect-[5/8]" : "aspect-[63/88]")}>
              <ProductImage product={h.product} grade={h.identity.grade} slabKey={h.key} frame={false} className="h-full w-full" />
            </HoloTilt>
          )}
        </div>
        {h.quantity > 1 && <span className="tabular absolute left-2.5 top-2.5 rounded-full bg-background/80 px-2 py-0.5 text-[11px] font-semibold ring-1 ring-border backdrop-blur">×{h.quantity}</span>}
        {/* A slab's own label already shows its grade. */}
        {holdingLabel(h) && !h.identity.grade && <span className={cn("absolute top-2.5", onMore ? "right-12" : "right-2.5", " rounded-full bg-background/80 px-2 py-0.5 text-[11px] font-medium text-muted backdrop-blur")}>{holdingLabel(h)}</span>}
      </div>
      <div className="mt-3 min-w-0 px-0.5">
        <p className="truncate text-[14px] font-medium">{h.product?.name ?? "Unknown product"}</p>
        <p className="truncate text-[12px] text-muted">{[h.product?.setName, h.product ? categoryOf(h.product) : null].filter(Boolean).join(" · ")}</p>
        <div className="mt-2 flex items-end justify-between gap-2">
          <div>
            {/* A price more than 3 days old shows dimmed (your own values never do). Same as the app. */}
            <p className={cn("hype-num tabular text-[20px] leading-none", h.priceStatus !== "manual" && isStalePrice(h.priceUpdatedAt) && "opacity-60")}>{money(h.value)}</p>
            <p className="tabular flex items-center gap-1 text-[12px] text-muted">
              {unitPrice(h)} ea
              <PriceStatus holding={h} />
            </p>
          </div>
          <div className="text-right">
            <DeltaPill ratio={h.unrealizedPct} />
            <Delta value={h.unrealized} className={cn("mt-1 block text-[12px]")} />
          </div>
        </div>
      </div>
    </Link>
  );
  if (!onMore) return link;
  return (
    <div className="relative">
      {link}
      <MoreButton onClick={() => onMore(h)} label={h.product?.name} className="glass absolute right-1.5 top-1.5 size-8 text-foreground" />
    </div>
  );
}
