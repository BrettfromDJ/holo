"use client";
/* eslint-disable @next/next/no-img-element -- set icons come from the pricing source's CDN */

import { ChevronLeft, ChevronRight, KeyRound, Library, Loader2, Search, SearchX, X } from "lucide-react";
import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Segmented } from "@/components/ui/segmented";
import { ProductImage } from "@/components/product/product-image";
import { categoryOf } from "@/lib/catalog";
import { SAMPLE_PRODUCTS } from "@/lib/demo/catalog";
import { money } from "@/lib/format";
import type { ProductTypeFilter, SearchHit, SetInfo } from "@/lib/pricing/types";
import { normalize, parseQuery, rankByQuery, scoreProduct } from "@/lib/search-query";
import { useStore } from "@/lib/store/collection-store";
import { priceKey } from "@/lib/types";
import { cn } from "@/lib/utils";

const SUGGESTIONS = ["Charizard", "Booster Box", "ETB", "Umbreon", "151", "UPC"];
const MIN_QUERY = 3;

// Sets rarely change; keep them for the browser session.
let setsCache: Promise<SetInfo[]> | null = null;
function loadSets(): Promise<SetInfo[]> {
  setsCache ??= fetch("/api/tcg/sets")
    .then(async (r) => {
      const body = await r.json();
      if (!r.ok) throw new Error(body?.error?.message ?? "Sets unavailable.");
      return body.sets as SetInfo[];
    })
    .catch((e) => {
      setsCache = null;
      throw e;
    });
  return setsCache;
}

function matchesType(hit: SearchHit, type: ProductTypeFilter) {
  return type === "all" || (type === "sealed" ? hit.product.kind === "sealed" : hit.product.kind === "single");
}

/**
 * Ticker-style product search with set browsing. Demo mode uses the sample
 * catalog locally; personal mode queries TCG API through the server, which
 * retries looser variants when the exact phrase finds nothing.
 */
/** "Pokemon Japan" → "Japan"; nothing for the English catalog. */
function regionLabel(gameName: string | null | undefined): string | null {
  if (!gameName || /^pok[eé]mon$/i.test(gameName.trim())) return null;
  return gameName.replace(/^pok[eé]mon\s*/i, "").trim() || gameName;
}

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
  const [sets, setSets] = useState<SetInfo[]>([]);
  const [activeSet, setActiveSet] = useState<SetInfo | null>(null);
  const [setProducts, setSetProducts] = useState<SearchHit[]>([]);
  const [showAllSets, setShowAllSets] = useState(false);
  const listRef = useRef<HTMLUListElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const sampleHits = useMemo<SearchHit[]>(
    () =>
      SAMPLE_PRODUCTS.map((p) => {
        const printing = p.printings?.[0] ?? null;
        return { product: data.products[p.id] ?? p, printing, market: data.prices[priceKey(p.id, printing)]?.market ?? null, priceUpdatedAt: null };
      }),
    [data.products, data.prices],
  );

  // Load sets once.
  useEffect(() => {
    if (unconfigured) return;
    if (demo) {
      const names = [...new Set(SAMPLE_PRODUCTS.map((p) => p.setName).filter((s): s is string => Boolean(s)))];
      setSets(names.map((name) => ({ id: name, name, abbreviation: null, releaseDate: null, iconUrl: null, imageUrl: null, cardCount: null })));
      return;
    }
    loadSets()
      .then(setSets)
      .catch(() => setSets([]));
  }, [demo, unconfigured]);

  // Products for the selected set.
  useEffect(() => {
    if (!activeSet) return;
    if (demo) {
      setSetProducts(sampleHits.filter((h) => h.product.setName === activeSet.name));
      return;
    }
    const ctrl = new AbortController();
    setLoading(true);
    setError(null);
    fetch(`/api/tcg/sets/${activeSet.id}/products?type=${type}`, { signal: ctrl.signal })
      .then(async (r) => {
        const body = await r.json();
        if (!r.ok) throw new Error(body?.error?.message ?? "Couldn't load this set.");
        setSetProducts(body.hits ?? []);
      })
      .catch((e: Error) => e.name !== "AbortError" && setError(e.message))
      .finally(() => !ctrl.signal.aborted && setLoading(false));
    return () => ctrl.abort();
  }, [activeSet, type, demo, sampleHits]);

  // Free-text search (only when not browsing a set).
  useEffect(() => {
    setCursor(0);
    if (activeSet) return;
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
  }, [q, type, demo, unconfigured, activeSet, sampleHits]);

  // Inside a set, the search box filters locally — no extra API calls.
  const visibleSetHits = useMemo(() => {
    const base = setProducts.filter((h) => matchesType(h, type));
    const query = q.trim();
    if (!query) return base;
    const parsed = parseQuery(query);
    return rankByQuery(base.filter((h) => scoreProduct(h.product, parsed) >= 0.4 || normalize(h.product.name).includes(normalize(query))), parsed);
  }, [setProducts, type, q]);

  const matchingSets = useMemo(() => {
    const query = q.trim();
    if (activeSet || query.length < 2 || !sets.length) return [];
    const parsed = parseQuery(query);
    const tokens = (parsed.core || parsed.text).split(" ").filter((t) => t.length >= 2);
    if (!tokens.length) return [];
    return sets.filter((s) => {
      const name = normalize(`${s.name} ${s.abbreviation ?? ""}`);
      return tokens.every((t) => name.includes(t));
    }).slice(0, 4);
  }, [q, sets, activeSet]);

  const results = activeSet ? visibleSetHits : hits;

  const openSet = (s: SetInfo) => {
    setActiveSet(s);
    setSetProducts([]);
    setQ("");
    setShowAllSets(false);
    inputRef.current?.focus();
  };

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Backspace" && !q && activeSet) {
      setActiveSet(null);
      return;
    }
    if (!results.length) return;
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setCursor((c) => Math.min(results.length - 1, c + 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setCursor((c) => Math.max(0, c - 1));
    } else if (e.key === "Enter") {
      e.preventDefault();
      onSelect(results[cursor]);
    }
  };

  useEffect(() => {
    listRef.current?.querySelector(`[data-index="${cursor}"]`)?.scrollIntoView({ block: "nearest" });
  }, [cursor]);

  const query = q.trim();
  const tooShort = !activeSet && query.length < (demo ? 2 : MIN_QUERY);

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div className="px-5 pt-5">
        <div className="relative flex h-12 items-center rounded-2xl bg-surface-2 focus-within:bg-surface-3">
          <Search className="pointer-events-none ml-3.5 size-[18px] shrink-0 text-subtle" />
          {activeSet && (
            <button
              onClick={() => setActiveSet(null)}
              className="ml-2 flex max-w-[45%] shrink-0 items-center gap-1 rounded-lg bg-surface px-2 py-1 text-[13px] font-medium"
              aria-label={`Leave ${activeSet.name}`}
            >
              <span className="truncate">{activeSet.name}</span>
              <X className="size-3.5 shrink-0 text-muted" />
            </button>
          )}
          <input
            ref={inputRef}
            autoFocus={autoFocus}
            value={q}
            onChange={(e) => setQ(e.target.value)}
            onKeyDown={onKeyDown}
            placeholder={activeSet ? "Filter this set" : demo ? "Search sample products" : "Search cards, sets, booster boxes, ETBs…"}
            aria-label="Search products"
            role="combobox"
            aria-expanded={results.length > 0}
            aria-controls="product-search-results"
            aria-activedescendant={results.length ? `search-hit-${cursor}` : undefined}
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
        ) : !activeSet && (tooShort || showAllSets) ? (
          <Browse sets={sets} showAll={showAllSets} setShowAll={setShowAllSets} onOpenSet={openSet} onSuggest={setQ} demo={demo} />
        ) : (
          <>
            {matchingSets.length > 0 && (
              <div className="px-3 pb-2">
                <p className="mb-2 text-[11px] font-medium uppercase tracking-wider text-subtle">Sets</p>
                <div className="flex flex-wrap gap-2">
                  {matchingSets.map((s) => (
                    <button key={s.id} onClick={() => openSet(s)} className="flex items-center gap-2 rounded-full bg-surface-2 py-1.5 pl-2 pr-3 text-[13px] hover:bg-surface-3">
                      <SetIcon set={s} className="size-5" />
                      {s.name}
                      {regionLabel(s.gameName) && <span className="text-subtle">· {regionLabel(s.gameName)}</span>}
                      <ChevronRight className="size-3.5 text-subtle" />
                    </button>
                  ))}
                </div>
              </div>
            )}
            {relaxed && results.length > 0 && (
              <p className="px-3 pb-2 text-[12px] text-muted">
                No exact match for “{query}”. Showing results for <span className="text-foreground">“{relaxed}”</span>.
              </p>
            )}
            {activeSet && !loading && !results.length ? (
              <EmptyState icon={SearchX} title="Nothing here" body={query ? `No ${type === "sealed" ? "sealed products" : type === "cards" ? "cards" : "products"} in ${activeSet.name} match “${query}”.` : `No ${type === "sealed" ? "sealed products" : type === "cards" ? "cards" : "products"} found in ${activeSet.name}.`} />
            ) : !activeSet && !loading && !results.length && !matchingSets.length ? (
              <EmptyState icon={SearchX} title="No matches" body={`Nothing found for “${query}”. Try fewer words, or browse a set.`}>
                <button onClick={() => setShowAllSets(true)} className="text-sm font-medium underline-offset-4 hover:underline">
                  Browse sets
                </button>
              </EmptyState>
            ) : (
              <ul ref={listRef} id="product-search-results" role="listbox" className="flex flex-col">
                {results.map((hit, i) => (
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

function Browse({
  sets,
  showAll,
  setShowAll,
  onOpenSet,
  onSuggest,
  demo,
}: {
  sets: SetInfo[];
  showAll: boolean;
  setShowAll: (v: boolean) => void;
  onOpenSet: (s: SetInfo) => void;
  onSuggest: (q: string) => void;
  demo: boolean;
}) {
  const [filter, setFilter] = useState("");
  const visible = showAll ? sets.filter((s) => normalize(s.name).includes(normalize(filter))) : sets.slice(0, 8);
  return (
    <div className="px-3 pt-1">
      {!showAll && (
        <>
          <p className="text-[11px] font-medium uppercase tracking-wider text-subtle">Try</p>
          <div className="mt-2 flex flex-wrap gap-2">
            {SUGGESTIONS.map((s) => (
              <button key={s} onClick={() => onSuggest(s)} className="rounded-full bg-surface-2 px-3 py-1.5 text-[13px] text-muted transition-colors hover:bg-surface-3 hover:text-foreground">
                {s}
              </button>
            ))}
          </div>
        </>
      )}
      {sets.length > 0 && (
        <div className={cn(!showAll && "mt-6")}>
          <div className="mb-1 flex items-center justify-between">
            {showAll ? (
              <button onClick={() => setShowAll(false)} className="-ml-1 flex items-center gap-1 text-[13px] font-medium text-muted hover:text-foreground">
                <ChevronLeft className="size-4" /> All sets
              </button>
            ) : (
              <p className="text-[11px] font-medium uppercase tracking-wider text-subtle">{demo ? "Sample sets" : "Browse by set"}</p>
            )}
            {!showAll && sets.length > 8 && (
              <button onClick={() => setShowAll(true)} className="text-[13px] font-medium text-muted hover:text-foreground">
                See all {sets.length}
              </button>
            )}
          </div>
          {showAll && (
            <input
              autoFocus
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
              placeholder="Filter sets"
              aria-label="Filter sets"
              className="mb-2 h-9 w-full rounded-xl bg-surface-2 px-3 text-[14px] outline-none placeholder:text-subtle"
            />
          )}
          <ul className="-mx-2">
            {visible.map((s) => (
              <li key={s.id}>
                <button onClick={() => onOpenSet(s)} className="flex w-full items-center gap-3 rounded-xl px-2 py-2 text-left hover:bg-surface-2">
                  <SetIcon set={s} className="size-9" />
                  <span className="min-w-0 flex-1">
                    <span className="flex items-center gap-2">
                      <span className="truncate text-[14px] font-medium">{s.name}</span>
                      {regionLabel(s.gameName) && <Badge variant="outline" className="shrink-0">{regionLabel(s.gameName)}</Badge>}
                    </span>
                    {(s.releaseDate || s.cardCount) && (
                      <span className="block text-[12px] text-muted">{[s.releaseDate?.slice(0, 4), s.cardCount ? `${s.cardCount} products` : null].filter(Boolean).join(" · ")}</span>
                    )}
                  </span>
                  <ChevronRight className="size-4 text-subtle" />
                </button>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

function SetIcon({ set, className }: { set: SetInfo; className?: string }) {
  const [failed, setFailed] = useState(false);
  const src = set.iconUrl ?? set.imageUrl;
  return (
    <span className={cn("flex shrink-0 items-center justify-center overflow-hidden rounded-lg bg-surface-2", className)}>
      {src && !failed ? <img src={src} alt="" className="h-full w-full object-contain p-1" onError={() => setFailed(true)} /> : <Library className="size-[55%] text-subtle" />}
    </span>
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
