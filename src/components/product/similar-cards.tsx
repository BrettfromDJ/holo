"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { ProductImage } from "@/components/product/product-image";
import { isOversized } from "@/lib/explore/movers";
import type { ExploreProduct } from "@/lib/explore/types";
import { money } from "@/lib/format";
import type { Product } from "@/lib/types";

/**
 * The card's name without its number and variant notes: "Charizard ex - 199/165" and
 * "Umbreon VMAX (Alternate Art Secret)" become "Charizard ex" and "Umbreon VMAX". Same as the
 * app's `OtherVersionsRow.baseName`.
 */
export function baseName(name: string): string {
  return name
    .replace(/\([^)]*\)|\[[^\]]*\]/g, " ")
    .replace(/\s+-\s+.*$/, "")
    .replace(/\s+#?[A-Za-z]{0,5}\d+(\/[A-Za-z]{0,5}\d+)?\s*$/, "")
    .replace(/\s+/g, " ")
    .trim();
}

/** Found this visit, by product (going back and forth costs nothing). */
const cache = new Map<string, ExploreProduct[]>();

/**
 * "Similar cards": the same card in other sets, printings and promos, priciest first. From our
 * stored catalog's search (no TCG API calls), like the app's `OtherVersionsRow`. Nothing shows
 * until some are found.
 */
export function SimilarCards({ product }: { product: Product }) {
  const [versions, setVersions] = useState<ExploreProduct[]>(() => cache.get(product.id) ?? []);

  useEffect(() => {
    const id = product.id;
    const hit = cache.get(id);
    if (hit) return setVersions(hit);
    setVersions([]);
    const base = baseName(product.name);
    if (product.kind !== "single" || base.length < 2) return;
    let cancelled = false;
    fetch(`/api/explore/search?q=${encodeURIComponent(base)}&limit=80`)
      .then((r) => (r.ok ? r.json() : null))
      .then((body: { products?: ExploreProduct[] } | null) => {
        if (cancelled || !body?.products) return;
        const wanted = base.toLowerCase();
        // One entry per product (search can list a product once per printing): its best price.
        const best = new Map<string, ExploreProduct>();
        for (const h of body.products) {
          const p = h.product;
          if (p.id === id || p.kind !== "single" || isOversized(p) || baseName(p.name).toLowerCase() !== wanted) continue;
          const have = best.get(p.id);
          if (have && (have.market ?? -1) >= (h.market ?? -1)) continue;
          best.set(p.id, h);
        }
        const list = [...best.values()].sort((a, b) => (b.market ?? -1) - (a.market ?? -1)).slice(0, 12);
        cache.set(id, list);
        setVersions(list);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [product.id, product.name, product.kind]);

  if (!versions.length) return null;
  return (
    <section className="mt-8">
      <h2 className="font-display text-[22px] leading-none tracking-[-0.02em]">Similar cards</h2>
      <div className="-mx-4 mt-3 overflow-x-auto px-4 pb-2 [scrollbar-width:none] sm:mx-0 sm:px-0">
        <ul className="flex gap-2.5">
          {versions.map((v) => (
            <li key={v.product.id} className="w-[150px] shrink-0">
              <Link
                href={`/product/${encodeURIComponent(v.product.id)}${v.printing ? `?printing=${encodeURIComponent(v.printing)}` : ""}`}
                aria-label={`${v.product.name}, ${v.product.setName ?? ""}, ${money(v.market)}`}
                className="relative block"
              >
                <ProductImage product={v.product} size="sm" frame={false} className="aspect-[63/88] w-full rounded-[4.5%/3.2%]" />
                {v.market !== null && (
                  <span className="tabular absolute bottom-2 left-2 rounded-full border border-white/10 bg-black/45 px-2 py-0.5 text-[12px] font-semibold text-white backdrop-blur-md">
                    {money(v.market)}
                  </span>
                )}
              </Link>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
