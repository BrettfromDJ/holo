"use client";

import { KeyRound, Loader2, Search, SearchX } from "lucide-react";
import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Segmented } from "@/components/ui/segmented";
import { ProductImage } from "@/components/product/product-image";
import { categoryOf } from "@/lib/catalog";
import { SAMPLE_PRODUCTS } from "@/lib/demo/catalog";
import { money } from "@/lib/format";
import type { ProductTypeFilter, SearchHit } from "@/lib/pricing/types";
import { parseQuery, rankByQuery, scoreProduct } from "@/lib/search-query";
import { useStore } from "@/lib/store/collection-store";
import { priceKey } from "@/lib/types";
import { cn } from "@/lib/utils";

const SUGGESTIONS = ["Charizard", "Booster Box", "ETB", "Umbreon", "151", "UPC"];
const MIN_QUERY = 3;

function matchesType(hit: SearchHit, type: ProductTypeFilter) {
  return type === "all" || (type === "sealed" ? hit.product.kind === "sealed" : hit.product.kind === "single");
}

/** "Pokemon Japan" → "Japan"; nothing for the English catalog. */
function regionLabel(gameName: string | null | undefined): string | null {
  if (!gameName || /^pok[eé]mon$/i.test(gameName.trim())) return null;
  return gameName.replace(/^pok[eé]mon\s*/i, "").trim() || gameName;
}

/**
 * Ticker-style product search. Demo mode uses the sample catalog locally;
 * personal mode queries TCG API through the server, which retries looser
 * variants when the exact phrase finds nothing.
 */
export function ProductSearch({ onSelect, autoFocus = true }: { onSelect: (hit: SearchHit) => void; autoFocus?: boolean }) {
  const { mode, integrations, data } = useStore();
  const demo = mode === "demo";
  const unconfigured = !demo && !integrations.tcgapi;

  const [q, setQ] = useState("");
  const [type, setType] = useState<ProductTypeFilter>("all");
  const [hits, setHits] = useState<SearchHit[]>([]);
  const [relaxed, setRelaxed] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [cursor, setCursor] = useState(0);
  const listRef = useRef<HTMLUListElement>(null);

  const sampleHits = useMemo<SearchHit[]>(
    () =>
      SAMPLE_PRODUCTS.map((p) => {
        const printing = p.printings?.[0] ?? null;
        return { product: data.products[p.id] ?? p, printing, market: data.prices[priceKey(p.id, printing)]?.market ?? null, priceUpdatedAt: null };
      }),
    [data.products, data.prices],
  );

  useEffect(() => {
    setCursor(0);
    const query = q.trim();
    setRelaxed(null);
    if (query.length < (demo ? 2 : MIN_QUERY) || unconfigured) {
      setHits([]);
      setError(null);
      return;
    }
    if (demo) {
      const parsed = parseQuery(query);
      setHits(rankByQuery(sampleHits.filter((h) => matchesType(h, type) && scoreProduct(h.product, parsed) >= 0.5), parsed));
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
        setRelaxed(body.relaxedQuery ?? null);
      } catch (err) {
        if ((err as Error).name !== "AbortError") setError((err as Error).message);
      } finally {
        if (!ctrl.signal.aborted) setLoading(false);
      }
    }, 400);
    return () => {
      clearTimeout(t);
      ctrl.abort();
    };
  }, [q, type, demo, unconfigured, sampleHits]);

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

  const query = q.trim();
  const tooShort = query.length < (demo ? 2 : MIN_QUERY);

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div className="px-5 pt-5">
        <div className="relative flex h-11 items-center rounded-xl border border-border bg-surface-2 focus-within:border-border-strong">
          <Search className="pointer-events-none ml-3.5 size-[18px] shrink-0 text-subtle" />
          <input
            autoFocus={autoFocus}
            value={q}
            onChange={(e) => setQ(e.target.value)}
            onKeyDown={onKeyDown}
            placeholder={demo ? "Search sample products" : "Search cards, booster boxes, ETBs…"}
            aria-label="Search products"
            role="combobox"
            aria-expanded={hits.length > 0}
            aria-controls="product-search-results"
            aria-activedescendant={hits.length ? `search-hit-${cursor}` : undefined}
            className="h-full min-w-0 flex-1 bg-transparent pl-2.5 pr-10 text-[16px] outline-none placeholder:text-subtle"
          />
          {loading && <Loader2 className="absolute right-3.5 size-4 animate-spin text-subtle" />}
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
        ) : tooShort ? (
          <div className="px-3 pt-1">
            <p className="text-[11px] font-medium uppercase tracking-wider text-subtle">Try</p>
            <div className="mt-2 flex flex-wrap gap-2">
              {SUGGESTIONS.map((s) => (
                <button key={s} onClick={() => setQ(s)} className="rounded-full bg-surface-2 px-3 py-1.5 text-[13px] text-muted transition-colors hover:bg-surface-3 hover:text-foreground">
                  {s}
                </button>
              ))}
            </div>
          </div>
        ) : (
          <>
            {relaxed && hits.length > 0 && (
              <p className="px-3 pb-2 text-[12px] text-muted">
                No exact match for “{query}”. Showing results for <span className="text-foreground">“{relaxed}”</span>.
              </p>
            )}
            {!loading && !hits.length ? (
              <EmptyState icon={SearchX} title="No matches" body={`Nothing found for “${query}”. Try fewer words or a different spelling.`} />
            ) : (
              <ul ref={listRef} id="product-search-results" role="listbox" className="flex flex-col">
                {hits.map((hit, i) => (
                  <li key={`${hit.product.id}-${hit.printing}-${i}`} id={`search-hit-${i}`} role="option" aria-selected={i === cursor} data-index={i}>
                    <button
                      onClick={() => onSelect(hit)}
                      onMouseEnter={() => setCursor(i)}
                      className={cn("flex w-full items-center gap-3.5 rounded-xl px-3 py-2.5 text-left transition-colors", i === cursor && "bg-surface-2")}
                    >
                      <ProductImage product={hit.product} size="xs" className="size-12 shrink-0 rounded-lg" />
                      <span className="min-w-0 flex-1">
                        <span className="flex items-center gap-2">
                          <span className="truncate text-[15px] font-medium">{hit.product.name}</span>
                          {regionLabel(hit.gameName) && <Badge variant="outline" className="shrink-0">{regionLabel(hit.gameName)}</Badge>}
                        </span>
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
          </>
        )}
      </div>
    </div>
  );
}

function EmptyState({ icon: Icon, title, body, children }: { icon: React.ElementType; title: string; body: string; children?: React.ReactNode }) {
  return (
    <div className="flex flex-col items-center px-8 py-12 text-center">
      <span className="flex size-12 items-center justify-center rounded-xl bg-surface-2">
        <Icon className="size-5 text-muted" />
      </span>
      <p className="mt-4 font-medium">{title}</p>
      <p className="mt-1 max-w-xs text-sm text-muted">{body}</p>
      {children && <div className="mt-4">{children}</div>}
    </div>
  );
}
