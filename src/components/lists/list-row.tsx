"use client";

import { Check, CheckCircle2, Circle, MoreHorizontal, type LucideIcon } from "lucide-react";
import Link from "next/link";
import type { ReactNode } from "react";
import { DeltaPill } from "@/components/product/delta";
import { ProductImage } from "@/components/product/product-image";
import { money, signedMoney, tone } from "@/lib/format";
import { priceKey, type NormalizedPrice, type Product } from "@/lib/types";
import { cn } from "@/lib/utils";

/** "Mega Darkrai ex - 116/084" → "Mega Darkrai ex" (the number is on the line under it). Same as the app's `shortName`. */
export function shortName(product: Pick<Product, "name" | "number"> | undefined | null): string {
  if (!product) return "Unknown";
  const n = product.number;
  if (n && product.name.endsWith(` - ${n}`)) return product.name.slice(0, -(n.length + 3));
  return product.name;
}

/** "Evolving Skies · #215/203", like the app's `Product.subtitle`. */
export function productSubtitle(product: Product | undefined | null): string {
  if (!product) return "";
  return [product.setName, product.number ? `#${product.number}` : null].filter(Boolean).join(" · ");
}

/** The watched printing's price, else any printing's (the app's `listPrice`). */
export function listPrice(prices: Record<string, NormalizedPrice>, productId: string, printing: string | null): NormalizedPrice | undefined {
  const exact = prices[priceKey(productId, printing)];
  if (exact && exact.market !== null) return exact;
  for (const p of Object.values(prices)) if (p.productId === productId && p.market !== null) return p;
  return exact;
}

export function productHref(id: string) {
  return `/product/${encodeURIComponent(id)}`;
}

/** The quiet line under a watched card: how far it is from your target. Only the figure is coloured when reached. */
function TargetLine({ price, target }: { price: number | null; target: number }) {
  if (price !== null && price <= target) {
    return (
      <span className="inline-flex items-center gap-1">
        <CheckCircle2 className="size-3.5 fill-lime text-background" aria-hidden />
        <span className="text-muted">Target</span>
        <span className="tabular text-up">{money(target)}</span>
        <span className="text-muted">reached</span>
      </span>
    );
  }
  if (price !== null && price > 0) {
    const away = Math.round(((price - target) / price) * 100);
    return (
      <span className="tabular">
        <span className="text-muted">Target </span>
        <span className="text-foreground">{money(target)}</span>
        <span className="text-muted"> · {away}% away</span>
      </span>
    );
  }
  return (
    <span className="tabular">
      <span className="text-muted">Target </span>
      <span className="text-foreground">{money(target)}</span>
    </span>
  );
}

/**
 * A watched or wished-for card (the app's `ListRow`): 48px art, its short name, set · number,
 * the price and today's move (no pill unless it moved ≥0.05%), and one quiet line: how far it is
 * from your target, or how much it's moved since you added it. Clicking opens the card; the ⋯
 * (`more`) sits at the end. In select mode the row ticks instead.
 */
export function ListRow({
  product,
  productId,
  price,
  change24hPct,
  target,
  addedPrice,
  more,
  selecting,
  selected,
  onToggle,
}: {
  product: Product | undefined;
  productId: string;
  price: number | null;
  /** Today's change, in percent. */
  change24hPct: number | null | undefined;
  target?: number | null;
  addedPrice?: number | null;
  more?: ReactNode;
  selecting?: boolean;
  selected?: boolean;
  onToggle?: () => void;
}) {
  const sinceAdded = target == null && addedPrice != null && addedPrice > 0 && price !== null && Math.abs(price - addedPrice) >= 0.01 ? price - addedPrice : null;
  const body = (
    <>
      <ProductImage product={product} size="xs" className="h-[67px] w-12 shrink-0" />
      <div className="min-w-0 flex-1">
        <p className="truncate text-[14px] font-medium">{shortName(product ?? { name: productId, number: null })}</p>
        <p className="truncate text-[12px] text-muted">{productSubtitle(product)}</p>
        {(target != null || sinceAdded !== null) && (
          <p className="mt-0.5 truncate text-[12px]">
            {target != null ? (
              <TargetLine price={price} target={target} />
            ) : (
              <span className="tabular">
                <span className={tone(sinceAdded) === "down" ? "text-down" : "text-up"}>{signedMoney(sinceAdded)}</span>
                <span className="text-muted"> since added</span>
              </span>
            )}
          </p>
        )}
      </div>
      <div className="flex shrink-0 flex-col items-end gap-1">
        <p className="tabular text-[14px] font-semibold">{money(price)}</p>
        {change24hPct != null && Math.abs(change24hPct) >= 0.05 && <DeltaPill ratio={change24hPct / 100} className="text-[11px]" />}
      </div>
    </>
  );

  return (
    <li className="list-row-panel flex items-center gap-1 rounded-2xl py-3.5 pl-4 pr-2">
      {selecting ? (
        <button type="button" onClick={onToggle} aria-pressed={selected} className="flex min-w-0 flex-1 items-center gap-3 pr-2 text-left">
          <SelectCheck on={Boolean(selected)} />
          {body}
        </button>
      ) : (
        <>
          <Link href={productHref(productId)} className="flex min-w-0 flex-1 items-center gap-3">
            {body}
          </Link>
          {more}
        </>
      )}
    </li>
  );
}

/** Round check for select mode: lime and filled when picked. */
export function SelectCheck({ on }: { on: boolean }) {
  return on ? (
    <span className="flex size-[22px] shrink-0 items-center justify-center rounded-full bg-lime text-[#0b0b0c]">
      <Check className="size-3.5" strokeWidth={3} aria-hidden />
    </span>
  ) : (
    <Circle className="size-[22px] shrink-0 text-subtle" aria-hidden />
  );
}

/** The ⋯ at the end of a row (the app's `RowMoreButton`); pass it as a dropdown trigger child. */
export function RowMoreIcon() {
  return <MoreHorizontal className="size-[18px]" />;
}

export const rowMoreClass = "flex h-11 w-10 shrink-0 items-center justify-center rounded-full text-muted outline-none transition-colors hover:bg-surface-3 hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring";

/**
 * Select mode's floating bar (the app's `selectBar`): Select all / Clear, then a solid pink
 * remove button with the count, on a glass capsule over the rows.
 */
export function SelectBar({ total, chosen, label, onAll, onRemove }: { total: number; chosen: number; label: (n: number) => string; onAll: () => void; onRemove: () => void }) {
  const allOn = total > 0 && chosen === total;
  return (
    <div className="pointer-events-none fixed inset-x-0 bottom-[calc(env(safe-area-inset-bottom)+80px)] z-50 lg:bottom-6 lg:pl-[232px] flex justify-center px-4 animate-rise">
      <div className="lists-glass pointer-events-auto flex w-full max-w-md items-center gap-2.5 rounded-full p-2">
        <button type="button" onClick={onAll} className="lists-glass h-[50px] shrink-0 rounded-full px-4 text-[15px] font-semibold">
          {allOn ? "Clear" : "Select all"}
        </button>
        <button
          type="button"
          onClick={onRemove}
          disabled={chosen === 0}
          className={cn("h-[50px] flex-1 rounded-full text-[16px] font-semibold", chosen === 0 ? "bg-foreground/[0.08] text-muted" : "bg-down text-white")}
        >
          {chosen === 0 ? "Select cards" : label(chosen)}
        </button>
      </div>
    </div>
  );
}

/**
 * Every empty page's look (the app's `EmptyPage`): an icon in a glass circle, a display heading,
 * one muted line, and one lime 44px button.
 */
export function EmptyPage({ icon: Icon, title, line, action }: { icon: LucideIcon; title: string; line: string; action: ReactNode }) {
  return (
    <div className="flex min-h-[55vh] flex-col items-center justify-center px-8 text-center">
      <span className="lists-glass mb-1.5 flex size-[72px] items-center justify-center rounded-full">
        <Icon className="size-[26px]" aria-hidden />
      </span>
      <h2 className="font-display mt-3.5 text-balance text-[24px] leading-tight">{title}</h2>
      <p className="mt-3.5 max-w-[300px] text-pretty text-[15px] text-muted">{line}</p>
      <div className="mt-6">{action}</div>
    </div>
  );
}

export const limePillClass = "inline-flex h-11 items-center justify-center gap-1.5 rounded-full bg-lime px-[22px] text-[15px] font-semibold text-[#0b0b0c] transition-transform active:scale-[0.97] [&_svg]:size-4";

/** "Select" / "Done" at the top right of a list page. */
export function SelectToggle({ selecting, onClick }: { selecting: boolean; onClick: () => void }) {
  return (
    <button type="button" onClick={onClick} className="h-9 rounded-full px-3 text-[15px] font-semibold text-foreground transition-colors hover:bg-surface-2">
      {selecting ? "Done" : "Select"}
    </button>
  );
}

/** A page's own big heading with something on the right (the app's in-page titles; no bar title). */
export function ListPageTitle({ title, right, sub }: { title: string; right?: ReactNode; sub?: ReactNode }) {
  return (
    <div className="mb-5 flex items-start justify-between gap-3">
      <div className="min-w-0">
        <h1 className="font-display text-balance text-[34px] leading-[1.05] sm:text-[40px]">{title}</h1>
        {sub && <div className="mt-2 text-[14px] text-muted">{sub}</div>}
      </div>
      {right && <div className="flex shrink-0 items-center gap-2 pt-1">{right}</div>}
    </div>
  );
}
