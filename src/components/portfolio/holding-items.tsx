"use client";

import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Delta, DeltaPill } from "@/components/product/delta";
import { PriceStatus } from "@/components/product/price-status";
import { HoloTilt } from "@/components/motion/holo-tilt";
import { ProductImage } from "@/components/product/product-image";
import { categoryOf } from "@/lib/catalog";
import type { HoldingView } from "@/lib/finance/portfolio";
import { money } from "@/lib/format";
import { cn } from "@/lib/utils";

export function holdingHref(h: HoldingView) {
  return `/product/${encodeURIComponent(h.identity.productId)}`;
}

export function holdingLabel(h: HoldingView): string | null {
  const parts: string[] = [];
  if (h.identity.grade) parts.push(`${h.identity.grade.company} ${h.identity.grade.grade}`);
  else if (h.identity.condition !== "Sealed" && h.identity.condition !== "Near Mint") parts.push(h.identity.condition);
  if (h.identity.printing && !["Normal", "Holofoil"].includes(h.identity.printing)) parts.push(h.identity.printing);
  return parts.length ? parts.join(" · ") : null;
}

/** Compact row for dashboard sections. `metric` picks the right-hand figure. */
export function HoldingMiniRow({ h, metric = "gain", change }: { h: HoldingView; metric?: "gain" | "value" | "change" | "added"; change?: number | null }) {
  return (
    <Link href={holdingHref(h)} className="group -mx-2 flex items-center gap-3 rounded-xl px-2 py-2 transition-colors hover:bg-surface-2">
      <ProductImage product={h.product} grade={h.identity.grade} size="xs" className="size-11 shrink-0 rounded-lg" />
      <div className="min-w-0 flex-1">
        <p className="truncate text-[14px] font-medium">{h.product?.name ?? "Unknown product"}</p>
        <p className="tabular truncate text-[12px] text-muted">
          {h.quantity} × {money(h.price)}
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
export function HoldingListRow({ h }: { h: HoldingView }) {
  return (
    <Link
      href={holdingHref(h)}
      className="group grid grid-cols-[3rem_1fr_auto] items-center gap-4 px-4 py-3 transition-colors hover:bg-surface-2 md:grid-cols-[3.5rem_minmax(0,2.4fr)_repeat(5,minmax(0,1fr))]"
    >
      <ProductImage product={h.product} grade={h.identity.grade} size="xs" className="size-12 rounded-lg md:size-14" />
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
        {money(h.price)}
      </div>
      <div className="tabular hidden text-right text-[14px] font-medium md:block">{money(h.value)}</div>
      <div className="text-right">
        <p className="tabular text-[14px] font-medium md:hidden">{money(h.value)}</p>
        <Delta value={h.unrealized} className="block text-[13px] md:text-[14px]" />
        <Delta ratio={h.unrealizedPct} pctOnly className="block text-[12px]" />
      </div>
    </Link>
  );
}

export function HoldingListHeader() {
  return (
    <div className="hidden grid-cols-[3.5rem_minmax(0,2.4fr)_repeat(5,minmax(0,1fr))] gap-4 border-b border-border px-4 pb-3 text-[12px] font-medium text-subtle md:grid">
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
export function HoldingTile({ h }: { h: HoldingView }) {
  const shape = h.identity.grade ? "slab" : h.product?.kind === "single" && h.product.imageUrl ? "card" : "sealed";
  return (
    <Link href={holdingHref(h)} className="group flex flex-col">
      <div className="relative">
        {/* The tilt (and its glare) wraps the item's own shape, not the square tile around it. */}
        <div className="flex aspect-square w-full items-center justify-center">
          {shape === "sealed" ? (
            <HoloTilt max={8} foil={false} className="h-full w-full">
              <ProductImage product={h.product} className="h-full w-full" />
            </HoloTilt>
          ) : (
            <HoloTilt max={8} foil={false} radius={shape === "slab" ? "7% / 4.4%" : "4.5% / 3.2%"} className={cn("h-full", shape === "slab" ? "aspect-[5/8]" : "aspect-[63/88]")}>
              <ProductImage product={h.product} grade={h.identity.grade} frame={false} className="h-full w-full" />
            </HoloTilt>
          )}
        </div>
        <span className="tabular absolute left-2.5 top-2.5 rounded-full bg-background/80 px-2 py-0.5 text-[11px] font-semibold backdrop-blur">×{h.quantity}</span>
        {/* A slab's own label already shows its grade. */}
        {holdingLabel(h) && !h.identity.grade && <span className="absolute right-2.5 top-2.5 rounded-full bg-background/80 px-2 py-0.5 text-[11px] font-medium text-muted backdrop-blur">{holdingLabel(h)}</span>}
      </div>
      <div className="mt-3 min-w-0 px-0.5">
        <p className="truncate text-[14px] font-medium">{h.product?.name ?? "Unknown product"}</p>
        <p className="truncate text-[12px] text-muted">{[h.product?.setName, h.product ? categoryOf(h.product) : null].filter(Boolean).join(" · ")}</p>
        <div className="mt-2 flex items-end justify-between gap-2">
          <div>
            <p className="tabular text-[15px] font-semibold">{money(h.value)}</p>
            <p className="tabular flex items-center gap-1 text-[12px] text-muted">
              {money(h.price)} ea
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
}
