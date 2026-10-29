"use client";

import { Loader2, Search } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { ProductImage } from "@/components/product/product-image";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { Segmented } from "@/components/ui/segmented";
import type { ExploreProduct } from "@/lib/explore/types";
import type { HoldingView } from "@/lib/finance/portfolio";
import { money } from "@/lib/format";
import { usePortfolio } from "@/lib/store/collection-store";
import type { Grade, Product } from "@/lib/types";

export type DealSide = "in" | "out";

/** A row in a deal. Out rows always come from your inventory (`holdingKey`). */
export interface DealItem {
  key: string;
  product: Product;
  printing?: string | null;
  /** Market value per unit when added. */
  market: number | null;
  qty: number;
  /** Negotiated price per unit; null means market × the rate. */
  price: number | null;
  /** This item's own share of market, overriding the side's slider. */
  rate?: number | null;
  /** A slab's grade, as scanned, for items coming in that aren't already held. */
  grade?: Grade | null;
  /** The holding this came from, when picked from your inventory. */
  holdingKey?: string;
  maxQty?: number;
}

/**
 * Pick what's coming in (anything: your inventory or the catalog) or going
 * out (only what you own). Search stays focused so you can add fast.
 */
export function DealPicker({ side, onClose, onPick }: { side: DealSide | null; onClose: () => void; onPick: (item: DealItem) => void }) {
  const { holdings } = usePortfolio({ ignoreFilter: true });
  const [source, setSource] = useState<"inventory" | "catalog">("inventory");
  const [q, setQ] = useState("");
  const [results, setResults] = useState<ExploreProduct[] | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (side) {
      setSource(side === "out" || holdings.length ? "inventory" : "catalog");
      setQ("");
      setResults(null);
    }
  }, [side, holdings.length]);

  useEffect(() => {
    if (source !== "catalog" || q.trim().length < 2) return setResults(null);
    setLoading(true);
    const t = window.setTimeout(() => {
      fetch(`/api/explore/search?q=${encodeURIComponent(q.trim())}`)
        .then((r) => (r.ok ? r.json() : { products: [] }))
        .then((b) => setResults(b.products ?? []))
        .catch(() => setResults([]))
        .finally(() => setLoading(false));
    }, 250);
    return () => window.clearTimeout(t);
  }, [q, source]);

  const mine = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return holdings.filter((h) => h.product && (!needle || `${h.product.name} ${h.product.setName} ${h.product.number ?? ""}`.toLowerCase().includes(needle)));
  }, [holdings, q]);

  const fromHolding = (h: HoldingView): DealItem => ({ key: `h:${h.key}`, product: h.product!, printing: h.identity.printing, market: h.price, qty: 1, price: null, holdingKey: h.key, maxQty: side === "out" ? h.quantity : undefined });

  return (
    <Dialog open={side !== null} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="h-[80dvh] sm:h-[600px] sm:max-w-[540px]" aria-describedby={undefined}>
        <div className="px-6 pt-6">
          <DialogTitle>{side === "out" ? "What's going out?" : "What's coming in?"}</DialogTitle>
          <div className="relative mt-4">
            <Search className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-subtle" />
            <input
              autoFocus
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder={source === "inventory" ? "Name, set or number" : "Search cards and sealed"}
              aria-label="Search"
              className="h-11 w-full rounded-2xl bg-surface-2 pl-10 pr-3 text-[15px] outline-none placeholder:text-subtle focus:bg-surface-3"
            />
          </div>
          {side === "in" && (
            <div className="mt-3">
              <Segmented
                ariaLabel="Source"
                size="sm"
                value={source}
                onChange={setSource}
                options={[
                  { value: "inventory", label: "Same as yours" },
                  { value: "catalog", label: "Catalog" },
                ]}
              />
            </div>
          )}
        </div>
        <div className="mt-3 min-h-0 flex-1 overflow-y-auto px-3 pb-4">
          {source === "inventory" ? (
            mine.length ? (
              mine.map((h) => (
                <Row
                  key={h.key}
                  product={h.product!}
                  sub={[h.identity.grade ? `${h.identity.grade.company} ${h.identity.grade.grade}` : h.identity.condition, side === "out" ? `${h.quantity} in stock` : null].filter(Boolean).join(" · ")}
                  price={h.price}
                  onClick={() => {
                    onPick(fromHolding(h));
                    onClose();
                  }}
                />
              ))
            ) : (
              <p className="px-3 py-10 text-center text-[14px] text-muted">Nothing in your inventory matches.</p>
            )
          ) : loading ? (
            <p className="flex items-center justify-center gap-2 py-10 text-[14px] text-muted">
              <Loader2 className="size-4 animate-spin" /> Searching…
            </p>
          ) : results === null ? (
            <p className="px-3 py-10 text-center text-[14px] text-muted">Type at least two letters to search the catalog.</p>
          ) : results.length ? (
            results.map((r) => (
              <Row
                key={r.product.id}
                product={r.product}
                sub={[r.product.setName, r.product.number && `#${r.product.number}`].filter(Boolean).join(" · ")}
                price={r.market}
                onClick={() => {
                  onPick({ key: `p:${r.product.id}:${r.printing ?? ""}`, product: r.product, printing: r.printing, market: r.market, qty: 1, price: null });
                  onClose();
                }}
              />
            ))
          ) : (
            <p className="px-3 py-10 text-center text-[14px] text-muted">Nothing in the catalog matches yet.</p>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}

function Row({ product, sub, price, onClick }: { product: Product; sub: string; price: number | null; onClick: () => void }) {
  return (
    <button onClick={onClick} className="flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left transition-colors hover:bg-surface-2">
      <ProductImage product={product} size="xs" className="size-11 shrink-0 rounded-lg" />
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[14px] font-medium">{product.name}</span>
        <span className="block truncate text-[12px] text-muted">{sub}</span>
      </span>
      <span className="tabular shrink-0 text-[14px] font-medium">{price === null ? <span className="text-subtle">No price</span> : money(price)}</span>
    </button>
  );
}
