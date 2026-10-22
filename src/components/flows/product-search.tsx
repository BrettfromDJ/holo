"use client";

import { KeyRound, Loader2, Search, SearchX } from "lucide-react";
import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Segmented } from "@/components/ui/segmented";
import { ProductImage } from "@/components/product/product-image";
import { categoryOf } from "@/lib/catalog";
import { searchSample } from "@/lib/demo/dataset";
import { money } from "@/lib/format";
import type { ProductTypeFilter, SearchHit } from "@/lib/pricing/types";
import { useStore } from "@/lib/store/collection-store";
import { priceKey } from "@/lib/types";
import { cn } from "@/lib/utils";

const SUGGESTIONS = ["Charizard", "Booster Box", "Elite Trainer Box", "Umbreon", "151", "Ultra Premium Collection"];

/**
 * Ticker-style product search. Demo mode searches the sample catalog locally;
 * personal mode queries TCG API through the server (the API key never
 * reaches the browser).
 */
export function ProductSearch({ onSelect, autoFocus = true }: { onSelect: (hit: SearchHit) => void; autoFocus?: boolean }) {
  const { mode, integrations, data } = useStore();
  const [q, setQ] = useState("");
  const [type, setType] = useState<ProductTypeFilter>("all");
  const [hits, setHits] = useState<SearchHit[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [cursor, setCursor] = useState(0);
  const listRef = useRef<HTMLUListElement>(null);
  const demo = mode === "demo";
  const unconfigured = !demo && !integrations.tcgapi;

  useEffect(() => {
    setCursor(0);
    const query = q.trim();
    if (query.length < 2 || unconfigured) {
      setHits([]);
      setError(null);
      return;
    }
    if (demo) {
      setHits(
        searchSample(query, type).map((p) => {
          const key = priceKey(p.id, p.printings?.[0] ?? null);
          return { product: data.products[p.id] ?? p, printing: p.printings?.[0] ?? null, market: data.prices[key]?.market ?? null, priceUpdatedAt: null };
        }),
      );
      return;
    }
    const ctrl = new AbortController();
    const t = setTimeout(async () => {
      setLoading(true);
      setError(null);
      try {
        const res = await fetch(`/api/tcg/search?q=${encodeURIComponent(query)}&type=${type}`, { signal: ctrl.signal });
        const body = await res.json();
        if (!res.ok) throw new Error(body?.error?.message ?? "Search failed.");
        setHits(body.hits ?? []);
      } catch (err) {
        if ((err as Error).name !== "AbortError") setError((err as Error).message);
      } finally {
        if (!ctrl.signal.aborted) setLoading(false);
      }
    }, 280);
    return () => {
      clearTimeout(t);
      ctrl.abort();
    };
  }, [q, type, demo, unconfigured, data.products, data.prices]);

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (!hits.length) return;
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setCursor((c) => Math.min(hits.length - 1, c + 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setCursor((c) => Math.max(0, c - 1));
    } else if (e.key === "Enter") {
      e.preventDefault();
      onSelect(hits[cursor]);
    }
  };

  useEffect(() => {
    listRef.current?.querySelector(`[data-index="${cursor}"]`)?.scrollIntoView({ block: "nearest" });
  }, [cursor]);

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div className="px-5 pt-5">
        <div className="relative">
          <Search className="pointer-events-none absolute left-3.5 top-1/2 size-[18px] -translate-y-1/2 text-subtle" />
          <input
            autoFocus={autoFocus}
            value={q}
            onChange={(e) => setQ(e.target.value)}
            onKeyDown={onKeyDown}
            placeholder={demo ? "Search sample products" : "Search Pokémon cards and sealed products"}
            aria-label="Search products"
            role="combobox"
            aria-expanded={hits.length > 0}
            aria-controls="product-search-results"
            aria-activedescendant={hits.length ? `search-hit-${cursor}` : undefined}
            className="h-12 w-full rounded-2xl bg-surface-2 pl-11 pr-10 text-[16px] outline-none placeholder:text-subtle focus:bg-surface-3"
          />
          {loading && <Loader2 className="absolute right-3.5 top-1/2 size-4 -translate-y-1/2 animate-spin text-subtle" />}
        </div>
        <div className="mt-3 flex items-center justify-between gap-2">
          <Segmented
            ariaLabel="Product type"
            size="sm"
            value={type}
            onChange={setType}
            options={[
              { value: "all", label: "All" },
              { value: "cards", label: "Singles" },
              { value: "sealed", label: "Sealed" },
            ]}
          />
          {demo && <Badge variant="sample">Sample catalog</Badge>}
        </div>
      </div>

      <div className="mt-3 min-h-[280px] flex-1 overflow-y-auto px-2 pb-3">
        {unconfigured ? (
          <EmptyState icon={KeyRound} title="Connect TCG API to search" body="Add a TCGAPI_KEY environment variable to search live Pokémon products and prices.">
            <Link href="/settings" className="text-sm font-medium underline-offset-4 hover:underline">
              Setup instructions
            </Link>
          </EmptyState>
        ) : error ? (
          <EmptyState icon={SearchX} title="Search is unavailable" body={error} />
        ) : q.trim().length < 2 ? (
          <div className="px-3 pt-2">
            <p className="text-xs font-medium uppercase tracking-wider text-subtle">Try</p>
            <div className="mt-3 flex flex-wrap gap-2">
              {SUGGESTIONS.map((s) => (
                <button key={s} onClick={() => setQ(s)} className="rounded-full bg-surface-2 px-3 py-1.5 text-[13px] text-muted transition-colors hover:bg-surface-3 hover:text-foreground">
                  {s}
                </button>
              ))}
            </div>
          </div>
        ) : !hits.length && !loading ? (
          <EmptyState icon={SearchX} title="No matches" body={`Nothing found for “${q.trim()}”. Try a set name or a shorter query.`} />
        ) : (
          <ul ref={listRef} id="product-search-results" role="listbox" className="flex flex-col">
            {hits.map((hit, i) => (
              <li key={`${hit.product.id}-${hit.printing}`} id={`search-hit-${i}`} role="option" aria-selected={i === cursor} data-index={i}>
                <button
                  onClick={() => onSelect(hit)}
                  onMouseEnter={() => setCursor(i)}
                  className={cn("flex w-full items-center gap-3.5 rounded-xl px-3 py-2.5 text-left transition-colors", i === cursor && "bg-surface-2")}
                >
                  <ProductImage product={hit.product} size="xs" className="size-12 shrink-0 rounded-lg" />
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[15px] font-medium">{hit.product.name}</span>
                    <span className="mt-0.5 block truncate text-[13px] text-muted">
                      {[hit.product.setName, categoryOf(hit.product), hit.printing && hit.printing !== "Normal" ? hit.printing : null].filter(Boolean).join(" · ")}
                    </span>
                  </span>
                  <span className="tabular shrink-0 text-right text-[15px] font-medium">{hit.market === null ? <span className="text-subtle">No price</span> : money(hit.market)}</span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

function EmptyState({ icon: Icon, title, body, children }: { icon: React.ElementType; title: string; body: string; children?: React.ReactNode }) {
  return (
    <div className="flex flex-col items-center px-8 py-12 text-center">
      <span className="flex size-12 items-center justify-center rounded-2xl bg-surface-2">
        <Icon className="size-5 text-muted" />
      </span>
      <p className="mt-4 font-medium">{title}</p>
      <p className="mt-1 max-w-xs text-sm text-muted">{body}</p>
      {children && <div className="mt-4">{children}</div>}
    </div>
  );
}
