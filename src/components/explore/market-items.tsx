"use client";

import { Check } from "lucide-react";
import Link from "next/link";
import { ProductImage } from "@/components/product/product-image";
import type { ExploreMover } from "@/lib/explore/movers";
import { money, signedPct } from "@/lib/format";
import { useHeroLink } from "@/lib/motion/hero";
import { cn } from "@/lib/utils";

function productHref(m: ExploreMover) {
  return `/product/${encodeURIComponent(m.product.id)}${m.printing ? `?printing=${encodeURIComponent(m.printing)}` : ""}`;
}

/** A stored percent change (12.5 = +12.5%), lime up and pink down. */
function Change({ value, className }: { value: number | null; className?: string }) {
  if (value === null) return <span className={cn("text-subtle", className)}>—</span>;
  return <span className={cn("tabular", value > 0 ? "text-up" : value < 0 ? "text-down" : "text-muted", className)}>{signedPct(value / 100, 1)}</span>;
}

/** A titled section with a muted subtitle, like the rest of Explore. */
export function MarketSection({ title, subtitle, children }: { title: string; subtitle: string; children: React.ReactNode }) {
  return (
    <section aria-label={title} className="mt-8">
      <div className="mb-3 flex items-baseline gap-3">
        <h2 className="font-display text-[18px] leading-none">{title}</h2>
        <span className="text-[12px] text-subtle">{subtitle}</span>
      </div>
      {children}
    </section>
  );
}

/** A sideways row of singles with their price and 7-day change. */
/** A sideways row of movers; `square` for sealed, which sits in a square well. */
export function MoverRow({ items, owned, square }: { items: ExploreMover[]; owned: Set<string>; square?: boolean }) {
  const hero = useHeroLink();
  return (
    <div className="-mx-4 overflow-x-auto px-4 pb-2 [scrollbar-width:none] sm:-mx-8 sm:px-8">
      <ul className="flex gap-4">
        {items.map((m) => {
          const href = productHref(m);
          return (
            <li key={m.product.id} className={cn("shrink-0", square ? "w-[132px]" : "w-[112px]")}>
              <Link href={href} onClick={(e) => hero(e, href)} className="group flex flex-col">
                <div className="relative">
                  <ProductImage product={m.product} size="sm" frame={!!square} className={cn("w-full transition-transform duration-500 ease-[var(--ease-apple)] group-hover:-translate-y-1", square ? "aspect-square rounded-2xl" : "aspect-[63/88]")} />
                  {owned.has(m.product.id) && (
                    <span className="absolute left-1.5 top-1.5 flex items-center gap-0.5 rounded-full bg-background/85 px-1.5 py-0.5 text-[10px] font-medium backdrop-blur">
                      <Check className="size-2.5" /> Owned
                    </span>
                  )}
                </div>
                <p className="mt-2 truncate text-[13px] font-medium">{m.product.name}</p>
                <p className="mt-0.5 flex items-baseline gap-1.5 text-[12px]">
                  <span className="tabular font-semibold">{money(m.market)}</span>
                  <Change value={m.change7dPct} />
                </p>
              </Link>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

/** Booster boxes as a compact list: art, name and set, market price, 30-day (and 7-day) change. */
export function BoosterBoxList({ items }: { items: ExploreMover[] }) {
  return (
    <div className="grid grid-cols-1 gap-x-6 sm:grid-cols-2">
      {items.map((m) => (
        <Link key={m.product.id} href={productHref(m)} className="flex min-w-0 items-center gap-3 rounded-2xl px-2 py-2 transition-colors hover:bg-surface-2/60">
          <ProductImage product={m.product} size="xs" className="size-12 shrink-0 rounded-xl" />
          <div className="min-w-0 flex-1">
            <p className="truncate text-[14px] font-medium">{m.product.name}</p>
            <p className="truncate text-[12px] text-muted">{[m.product.setName, m.gameName].filter(Boolean).join(" · ")}</p>
          </div>
          <div className="shrink-0 text-right">
            <p className="tabular text-[14px] font-semibold">{money(m.market)}</p>
            <p className="text-[11px] text-subtle">
              <Change value={m.change30dPct} /> 30d · <Change value={m.change7dPct} /> 7d
            </p>
          </div>
        </Link>
      ))}
    </div>
  );
}
