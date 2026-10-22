"use client";

import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Delta, DeltaPill } from "@/components/product/delta";
import { PriceStatus } from "@/components/product/price-status";
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
    <Link href={holdingHref(h)} className="group -mx-3 flex items-center gap-4 rounded-2xl px-3 py-2.5 transition-colors hover:bg-surface-2">
      <ProductImage product={h.product} size="xs" className="size-14 shrink-0 rounded-2xl" />
      <div className="min-w-0 flex-1">
        <p className="truncate text-[15px] font-semibold">{h.product?.name ?? "Unknown product"}</p>
        <p className="tabular mt-0.5 truncate text-[13px] text-muted">
          {h.quantity} × {money(h.price)}
          {holdingLabel(h) && <span> · {holdingLabel(h)}</span>}
        </p>
      </div>
      <div className="shrink-0 text-right">
        <p className="tabular text-[15px] font-bold">{money(h.value)}</p>
        {metric === "change" ? (
          <DeltaPill ratio={change ?? null} className="mt-1" />
        ) : metric === "added" ? (
          <p className="tabular text-[13px] text-muted">{h.lastAcquired}</p>
        ) : (
          <Delta value={h.unrealized} ratio={h.unrealizedPct} className="text-[13px] font-medium" pctOnly={metric === "value"} />
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
      className="group grid grid-cols-[3.5rem_1fr_auto] items-center gap-4 px-5 py-3 transition-colors hover:bg-surface-2/70 md:grid-cols-[3.5rem_minmax(0,2.4fr)_repeat(5,minmax(0,1fr))]"
    >
      <ProductImage product={h.product} size="xs" className="size-14 rounded-2xl" />
      <div className="min-w-0">
        <p className="truncate text-[15px] font-semibold">{h.product?.name ?? "Unknown product"}</p>
        <p className="mt-0.5 flex items-center gap-1.5 truncate text-[13px] text-muted">
          <span className="truncate">{[h.product?.setName, h.product ? categoryOf(h.product) : null].filter(Boolean).join(" · ")}</span>
          {holdingLabel(h) && (
            <Badge variant="outline" className="shrink-0">
              {holdingLabel(h)}
            </Badge>
          )}
        </p>
      </div>
      <div className="tabular hidden text-right text-[15px] text-muted md:block">{h.quantity}</div>
      <div className="tabular hidden text-right text-[15px] text-muted md:block">{money(h.avgCost)}</div>
      <div className="tabular hidden items-center justify-end gap-1.5 text-right text-[15px] md:flex">
        <PriceStatus holding={h} />
        {money(h.price)}
      </div>
      <div className="tabular hidden text-right text-[15px] font-bold md:block">{money(h.value)}</div>
      <div className="flex flex-col items-end gap-1 text-right">
        <p className="tabular text-[15px] font-bold md:hidden">{money(h.value)}</p>
        <Delta value={h.unrealized} className="block text-[14px] font-medium" />
        <DeltaPill ratio={h.unrealizedPct} />
      </div>
    </Link>
  );
}

export function HoldingListHeader() {
  return (
    <div className="hidden grid-cols-[3.5rem_minmax(0,2.4fr)_repeat(5,minmax(0,1fr))] gap-4 border-b border-border px-5 pb-3 text-[13px] font-semibold text-subtle md:grid">
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
  return (
    <Link
      href={holdingHref(h)}
      className="group flex flex-col rounded-[1.75rem] bg-surface p-2.5 shadow-card transition-[transform,box-shadow] duration-300 ease-[var(--ease-apple)] hover:-translate-y-1 hover:shadow-lift dark:border dark:border-border"
    >
      <div className="relative">
        <ProductImage product={h.product} className="aspect-square w-full rounded-[1.35rem]" />
        <span className="tabular absolute left-2.5 top-2.5 rounded-full bg-surface/90 px-2.5 py-1 text-[12px] font-bold shadow-card backdrop-blur">×{h.quantity}</span>
        {holdingLabel(h) && <span className="absolute right-2.5 top-2.5 rounded-full bg-surface/90 px-2.5 py-1 text-[12px] font-semibold text-muted shadow-card backdrop-blur">{holdingLabel(h)}</span>}
      </div>
      <div className="min-w-0 px-2 pb-1.5 pt-3">
        <p className="truncate text-[15px] font-semibold">{h.product?.name ?? "Unknown product"}</p>
        <p className="truncate text-[13px] text-muted">{[h.product?.setName, h.product ? categoryOf(h.product) : null].filter(Boolean).join(" · ")}</p>
        <div className="mt-3 flex items-end justify-between gap-2">
          <div>
            <p className="tabular text-[18px] font-bold tracking-tight">{money(h.value)}</p>
            <p className="tabular flex items-center gap-1 text-[13px] text-muted">
              {money(h.price)} ea
              <PriceStatus holding={h} />
            </p>
          </div>
          <div className="text-right">
            <DeltaPill ratio={h.unrealizedPct} />
            <Delta value={h.unrealized} className={cn("mt-1 block text-[13px] font-medium")} />
          </div>
        </div>
      </div>
    </Link>
  );
}
