"use client";

import { Activity } from "lucide-react";
import Link from "next/link";
import { useMemo } from "react";
import { ProductImage } from "@/components/product/product-image";
import type { HoldingView } from "@/lib/finance/portfolio";
import { money, signedPct } from "@/lib/format";
import { useStore } from "@/lib/store/collection-store";
import { priceKey, type Product } from "@/lib/types";
import { cn } from "@/lib/utils";

interface Tick {
  key: string;
  product: Product;
  price: number;
  change: number;
  watching: boolean;
}

function shortName(name: string) {
  return name.replace(/\s*\(.*?\)\s*/g, " ").replace(/\s+-\s+\d+\/\d+$/, "").trim();
}

/**
 * Stock-ticker strip of today's moves across everything you own or watch,
 * biggest movers first. Pauses on hover; reduced-motion users get a static,
 * scrollable row.
 */
export function MarketPulse({ holdings }: { holdings: HoldingView[] }) {
  const { data } = useStore();

  const ticks = useMemo(() => {
    const out = new Map<string, Tick>();
    for (const h of holdings) {
      if (!h.product || h.price === null || h.dayChangePct === null || h.identity.grade) continue;
      const key = priceKey(h.identity.productId, h.identity.printing);
      if (!out.has(key)) out.set(key, { key, product: h.product, price: h.price, change: h.dayChangePct, watching: false });
    }
    for (const w of data.watchlist) {
      const key = priceKey(w.productId, w.printing);
      const p = data.prices[key];
      const product = data.products[w.productId];
      if (out.has(key) || !product || p?.market == null || p.change24hPct == null) continue;
      out.set(key, { key, product, price: p.market, change: p.change24hPct / 100, watching: true });
    }
    return [...out.values()]
      .filter((t) => Math.abs(t.change) >= 0.0005)
      .sort((a, b) => Math.abs(b.change) - Math.abs(a.change))
      .slice(0, 24);
  }, [holdings, data.watchlist, data.prices, data.products]);

  if (ticks.length < 3) return null;
  const up = ticks.filter((t) => t.change > 0).length;

  return (
    <section aria-label="Market pulse" className="marquee group relative -mx-4 -mt-6 mb-8 flex sm:-mt-10 items-center overflow-hidden border-y border-border bg-surface/40 sm:-mx-8">
      <div className="z-10 flex shrink-0 items-center gap-2 border-r border-border bg-background px-4 py-2.5 sm:px-8">
        <span className="relative flex size-2">
          <span className="absolute inline-flex size-full animate-ping rounded-full bg-up opacity-60" />
          <span className="relative inline-flex size-2 rounded-full bg-up" />
        </span>
        <span className="text-[11px] font-medium font-mono uppercase tracking-[0.06em] text-muted">
          <Activity className="mr-1 inline size-3.5 -translate-y-px" />
          Pulse
        </span>
        <span className="tabular hidden text-[11px] text-subtle sm:inline">
          {up}↑ {ticks.length - up}↓
        </span>
      </div>
      <div className="relative min-w-0 flex-1 overflow-hidden [mask-image:linear-gradient(90deg,transparent,black_4%,black_96%,transparent)]">
        <div className="marquee-track flex w-max motion-reduce:animate-none" style={{ "--marquee-duration": `${Math.max(30, ticks.length * 5)}s` } as React.CSSProperties}>
          {[0, 1].map((copy) => (
            <ul key={copy} aria-hidden={copy === 1} className="flex shrink-0">
              {ticks.map((t) => (
                <li key={t.key}>
                  <Link
                    href={`/product/${encodeURIComponent(t.product.id)}`}
                    tabIndex={copy === 1 ? -1 : undefined}
                    className="flex items-center gap-2.5 px-5 py-2.5 transition-colors hover:bg-surface-2/60"
                  >
                    <ProductImage product={t.product} size="xs" className="size-6 rounded-md" />
                    <span className="max-w-[180px] truncate text-[13px] font-medium">{shortName(t.product.name)}</span>
                    {t.watching && <span className="rounded bg-surface-2 px-1 text-[9px] font-medium font-mono uppercase tracking-[0.06em] text-subtle">Watch</span>}
                    <span className="tabular text-[13px] text-muted">{money(t.price)}</span>
                    <span className={cn("tabular text-[13px] font-semibold", t.change > 0 ? "text-up" : "text-down")}>
                      {t.change > 0 ? "▲" : "▼"} {signedPct(t.change).replace(/^[+-]/, "")}
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          ))}
        </div>
      </div>
    </section>
  );
}
