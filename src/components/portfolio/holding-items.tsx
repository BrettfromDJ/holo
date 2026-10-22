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
    <Link href={holdingHref(h)} className="group -mx-2 flex items-center gap-3 rounded-lg px-2 py-1.5 transition-colors hover:bg-surface-2">
      <ProductImage product={h.product} size="xs" className="size-8 shrink-0 rounded-md" />
      <div className="min-w-0 flex-1">
        <p className="truncate text-[13px] font-medium">{h.product?.name ?? "Unknown product"}</p>
        <p className="tabular truncate text-[11px] text-muted">
          {h.quantity} × {money(h.price)}
          {holdingLabel(h) && <span> · {holdingLabel(h)}</span>}
        </p>
      </div>
      <div className="shrink-0 text-right">
        <p className="tabular text-[13px] font-semibold">{money(h.value)}</p>
        {metric === "change" ? (
          <DeltaPill ratio={change ?? null} className="mt-0.5" />
        ) : metric === "added" ? (
          <p className="tabular text-[12px] text-muted">{h.lastAcquired}</p>
        ) : (
          <Delta value={h.unrealized} ratio={h.unrealizedPct} className="text-[11px]" pctOnly={metric === "value"} />
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
      className="group grid grid-cols-[2.5rem_1fr_auto] items-center gap-4 px-4 py-2 transition-colors hover:bg-surface-2/70 md:grid-cols-[2.5rem_minmax(0,2.4fr)_repeat(5,minmax(0,1fr))]"
    >
      <ProductImage product={h.product} size="xs" className="size-10 rounded-md" />
      <div className="min-w-0">
        <p className="truncate text-[13px] font-semibold">{h.product?.name ?? "Unknown product"}</p>
        <p className="mt-0.5 flex items-center gap-1.5 truncate text-[12px] text-muted">
          <span className="truncate">{[h.product?.setName, h.product ? categoryOf(h.product) : null].filter(Boolean).join(" · ")}</span>
          {holdingLabel(h) && (
            <Badge variant="outline" className="shrink-0">
              {holdingLabel(h)}
            </Badge>
          )}
        </p>
      </div>
      <div className="tabular hidden text-right text-[13px] text-muted md:block">{h.quantity}</div>
      <div className="tabular hidden text-right text-[13px] text-muted md:block">{money(h.avgCost)}</div>
      <div className="tabular hidden items-center justify-end gap-1.5 text-right text-[13px] md:flex">
        <PriceStatus holding={h} />
        {money(h.price)}
      </div>
      <div className="tabular hidden text-right text-[13px] font-semibold md:block">{money(h.value)}</div>
      <div className="flex flex-col items-end gap-1 text-right">
        <p className="tabular text-[13px] font-semibold md:hidden">{money(h.value)}</p>
        <Delta value={h.unrealized} className="block text-[12px]" />
        <DeltaPill ratio={h.unrealizedPct} />
      </div>
    </Link>
  );
}

export function HoldingListHeader() {
  return (
    <div className="hidden grid-cols-[2.5rem_minmax(0,2.4fr)_repeat(5,minmax(0,1fr))] gap-4 border-b border-border px-4 pb-2.5 text-[11px] font-medium text-subtle md:grid">
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
    <Link href={holdingHref(h)} className="group flex flex-col">
      <div className="relative">
        <ProductImage product={h.product} className="aspect-square w-full rounded-xl border border-border transition-colors duration-300 group-hover:border-border-strong" />
        <span className="tabular absolute left-2 top-2 rounded-[5px] bg-background/80 px-1.5 py-0.5 text-[11px] font-semibold backdrop-blur">×{h.quantity}</span>
        {holdingLabel(h) && <span className="absolute right-2 top-2 rounded-[5px] bg-background/80 px-1.5 py-0.5 text-[11px] font-medium text-muted backdrop-blur">{holdingLabel(h)}</span>}
      </div>
      <div className="mt-3 min-w-0 px-0.5">
        <p className="truncate text-[13px] font-semibold">{h.product?.name ?? "Unknown product"}</p>
        <p className="truncate text-[12px] text-muted">{[h.product?.setName, h.product ? categoryOf(h.product) : null].filter(Boolean).join(" · ")}</p>
        <div className="mt-2 flex items-end justify-between gap-2">
          <div>
            <p className="tabular text-[14px] font-semibold">{money(h.value)}</p>
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
