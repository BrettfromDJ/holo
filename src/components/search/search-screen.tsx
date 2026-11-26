"use client";

import { ArrowUpLeft, Check, History, Plus, Search, X, Zap } from "lucide-react";
import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { ownedLabel, useOwnedIds, useOwnedQuantities } from "@/components/explore/explore-items";
import { SearchFilterBar } from "@/components/explore/search-filters";
import { ProductImage } from "@/components/product/product-image";
import { withEditionArt } from "@/lib/editions";
import { applyFilters, groupByKind, NO_FILTERS, type SearchFilters } from "@/lib/explore/filters";
import type { ExploreProduct } from "@/lib/explore/types";
import { usePagedCatalogSearch } from "@/lib/explore/use-catalog-search";
import { money } from "@/lib/format";
import { shortGameName } from "@/lib/games";
import { priceAge } from "@/lib/price-info";
import { clearSearchHistory, forgetQuery, rememberQuery, rememberViewed, useSearchHistory } from "@/lib/search-history";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";

function hrefOf(item: Pick<ExploreProduct, "product" | "printing">) {
  return `/product/${encodeURIComponent(item.product.id)}${item.printing ? `?printing=${encodeURIComponent(item.printing)}` : ""}`;
}

/** A mono section label with something on the right (the app's header(_:trailing:)). */
function Header({ title, children, className }: { title: string; children?: React.ReactNode; className?: string }) {
  return (
    <div className={cn("flex items-center justify-between gap-3 pb-1.5 pt-2", className)}>
      <h2 className="tabular font-mono text-[11px] uppercase tracking-[0.08em] text-subtle">{title}</h2>
      {children}
    </div>
  );
}

/**
 * Search, like the app's SearchScreen: ready to type. Before typing, your recent searches and
 * what you looked at lately; while typing, matches from your own collection first, then every
 * card and sealed product in Corodex's catalog (40 at a time) with filters. The live catalog (a
 * paid TCG API call) is only asked when you tap "Search the live catalog".
 */
export function SearchScreen({ initialQuery = "" }: { initialQuery?: string }) {
  const [query, setQuery] = useState(initialQuery);
  const input = useRef<HTMLInputElement>(null);
  const q = query.trim();
  const { state, loadMore, loadingMore, searchLive, liveSearching, liveTried } = usePagedCatalogSearch(query);
  const history = useSearchHistory();
  const { data } = useStore();
  const { holdings } = usePortfolio({ ignoreFilter: true });
  const owned = useOwnedIds();
  const ownedQty = useOwnedQuantities();
  const watched = useMemo(() => new Set(data.watchlist.map((w) => w.productId)), [data.watchlist]);
  const [filters, setFilters] = useState<SearchFilters>(NO_FILTERS);

  useEffect(() => {
    // Straight into typing, unless arriving with a search to show.
    if (!initialQuery) input.current?.focus();
  }, [initialQuery]);

  // The query in the address bar, so a search can be shared or reloaded.
  useEffect(() => {
    const t = window.setTimeout(() => {
      const url = new URL(window.location.href);
      if (q) url.searchParams.set("q", q);
      else url.searchParams.delete("q");
      window.history.replaceState(window.history.state, "", url);
    }, 400);
    return () => window.clearTimeout(t);
  }, [q]);

  // A new search starts unfiltered (keeping the sort).
  useEffect(() => setFilters((f) => ({ ...NO_FILTERS, sort: f.sort })), [q]);

  const mine = useMemo(() => {
    if (q.length < 2) return [];
    const lower = q.toLowerCase();
    return holdings
      .filter((h) => h.product && (h.product.name.toLowerCase().includes(lower) || (h.product.setName ?? "").toLowerCase().includes(lower) || (h.product.number ?? "").toLowerCase().startsWith(lower)))
      .slice(0, 4);
  }, [holdings, q]);

  const results = useMemo(() => (state?.status === "ready" ? state.data : []), [state]);
  const shown = useMemo(() => applyFilters(results, filters, { owned, watched }), [results, filters, owned, watched]);
  // Cards and sealed under their own headings, unless the Type filter already picked one.
  const groups = useMemo(() => (filters.type === "all" ? groupByKind(shown) : [{ kind: filters.type, title: "", items: shown }]), [shown, filters.type]);
  const searching = q.length >= 2 && (state?.status === "loading" || (state?.status === "ready" && state.query !== q));
  const answered = state?.status === "ready" && state.query === q;
  const more = state?.status === "ready" && !state.live && state.fetched < state.total;

  // At the end of what's loaded, fetch the next batch.
  const sentinel = useRef<HTMLDivElement>(null);
  const loadMoreRef = useRef(loadMore);
  loadMoreRef.current = loadMore;
  useEffect(() => {
    const el = sentinel.current;
    if (!el || !more) return;
    const io = new IntersectionObserver((entries) => entries.some((e) => e.isIntersecting) && loadMoreRef.current(), { rootMargin: "600px" });
    io.observe(el);
    return () => io.disconnect();
  }, [more, results.length]);

  const open = (item: Pick<ExploreProduct, "product" | "printing" | "market">) => {
    rememberQuery(query);
    rememberViewed(item);
  };

  return (
    <div className="animate-fade-in">
      <h1 className="sr-only">Search</h1>
      <div className="sticky top-[calc(3.5rem+env(safe-area-inset-top))] z-20 -mx-4 bg-background/85 px-4 pb-2.5 pt-2 backdrop-blur-xl sm:-mx-8 sm:px-8 lg:top-0">
        <form
          role="search"
          onSubmit={(e) => {
            e.preventDefault();
            rememberQuery(query);
            input.current?.blur();
          }}
          className="glass flex h-12 items-center gap-2.5 rounded-full px-4"
        >
          <Search className="size-4 shrink-0 text-muted" strokeWidth={2.5} aria-hidden />
          <input
            ref={input}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search any card or sealed product"
            aria-label="Search any card or sealed product"
            autoCapitalize="none"
            autoCorrect="off"
            spellCheck={false}
            enterKeyHint="search"
            className="h-full min-w-0 flex-1 bg-transparent text-[16px] text-foreground outline-none placeholder:text-subtle"
          />
          {query && (
            <button type="button" onClick={() => (setQuery(""), input.current?.focus())} aria-label="Clear" className="flex size-6 items-center justify-center rounded-full bg-white/25 text-background hover:bg-white/40">
              <X className="size-3.5" strokeWidth={3} />
            </button>
          )}
        </form>
      </div>

      {q.length < 2 ? (
        <Idle queries={history.queries} viewed={history.viewed} onPick={setQuery} onOpen={open} />
      ) : (
        <div className="pb-10">
          {mine.length > 0 && (
            <section aria-label="In your collection" className="mb-3.5">
              <Header title="In your collection" />
              <div className="fade-row -mx-4 overflow-x-auto px-4 [scrollbar-width:none] sm:-mx-8 sm:px-8 [&::-webkit-scrollbar]:hidden">
                <div className="flex gap-3">
                  {mine.map((h) => {
                    const item = { product: h.product!, printing: h.identity.printing ?? null, market: h.price };
                    return (
                      <Link key={h.key} href={hrefOf(item)} onClick={() => open(item)} className="w-[84px] shrink-0">
                        <ProductImage product={h.product} size="sm" frame={h.product?.kind === "sealed"} grade={h.identity.grade} className="h-[117px] w-[84px]" />
                        <p className="mt-1.5 truncate text-[12px] font-medium text-white">{h.product?.name}</p>
                        <p className="tabular flex items-baseline gap-1 text-[12px] font-semibold text-white">
                          {money(h.price === null ? null : h.price * h.quantity)}
                          {h.quantity > 1 && <span className="text-[11px] font-normal text-muted">×{Math.round(h.quantity)}</span>}
                        </p>
                      </Link>
                    );
                  })}
                </div>
              </div>
            </section>
          )}

          <Header title={!answered ? "Searching the catalog…" : shown.length === results.length ? `${state.total.toLocaleString()} in the catalog` : `${shown.length} of ${results.length} loaded match`} />
          {answered && state.fuzzy && results.length > 0 && <p className="pb-2 text-[13px] text-muted">Showing close matches for &ldquo;{q}&rdquo;</p>}
          {answered && results.length > 0 && (
            <div className="pb-2">
              <SearchFilterBar items={results} filters={filters} onChange={setFilters} />
            </div>
          )}

          {state?.status === "error" && state.query === q ? (
            <p className="py-4 text-[14px] text-down">{state.message}</p>
          ) : !answered && !results.length ? (
            Array.from({ length: 5 }, (_, i) => <PlaceholderRow key={i} />)
          ) : answered && !results.length ? (
            <div className="space-y-3 py-4">
              <p className="text-[16px] font-semibold">{liveTried ? `Nothing found for “${q}”, even live` : `Nothing in Corodex's catalog for “${q}”`}</p>
              <p className="text-[14px] text-muted">Try fewer words, the set name, or the card number (like&nbsp;215/203).</p>
              {!liveTried && (
                // The live catalog has things not synced yet, but each look is a paid TCG API call: only on a tap.
                <button type="button" onClick={searchLive} disabled={liveSearching} className="btn-3d btn-3d-dark inline-flex h-[42px] items-center gap-2 rounded-full bg-surface-2 px-4 text-[14px] font-semibold text-white disabled:opacity-60">
                  <Zap className="size-4 fill-current" /> {liveSearching ? "Searching the live catalog…" : "Search the live catalog"}
                </button>
              )}
            </div>
          ) : shown.length === 0 ? (
            <button type="button" onClick={() => setFilters({ ...NO_FILTERS, sort: filters.sort })} className="py-4 text-[14px] text-muted hover:text-foreground">
              No results match these filters. Clear filters
            </button>
          ) : null}

          <div className={cn(searching && results.length > 0 && "opacity-60 transition-opacity")}>
            {groups.map((g) =>
              g.items.length ? (
                <div key={g.kind}>
                  {g.title && (
                    <Header title={g.title} className="mt-1.5">
                      <span className="tabular font-mono text-[11px] text-subtle">{g.items.length}</span>
                    </Header>
                  )}
                  <ul className="grid lg:grid-cols-2 lg:gap-x-6">
                    {g.items.map((item) => (
                      <li key={`${item.product.id}|${item.printing}`}>
                        <ResultRow item={item} ownedQty={ownedQty.get(item.product.id) ?? 0} onOpen={() => open(item)} />
                      </li>
                    ))}
                  </ul>
                </div>
              ) : null,
            )}
          </div>

          {more && (
            <div ref={sentinel} className="tabular py-4 text-center text-[13px] text-muted">
              {loadingMore ? "Loading more" : "More"} · {results.length} of {state.status === "ready" ? state.total.toLocaleString() : ""}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

/** Before typing: recent searches (tap to search again, × to forget one, Clear) and recently viewed. */
function Idle({ queries, viewed, onPick, onOpen }: { queries: string[]; viewed: ExploreProduct[]; onPick: (q: string) => void; onOpen: (item: ExploreProduct) => void }) {
  if (!queries.length && !viewed.length) {
    return <p className="py-6 text-[14px] text-muted">Search every card and sealed product in Corodex&apos;s catalog, any game. Try a name, a set, or a number like 215/203.</p>;
  }
  return (
    <div className="pb-10">
      {queries.length > 0 && (
        <section aria-label="Recent searches">
          <Header title="Recent searches">
            <button type="button" onClick={clearSearchHistory} className="text-[13px] font-medium text-muted hover:text-foreground">
              Clear
            </button>
          </Header>
          <ul>
            {queries.map((q) => (
              <li key={q} className="group flex h-10 items-center gap-3">
                <button type="button" onClick={() => onPick(q)} className="flex min-w-0 flex-1 items-center gap-3 self-stretch text-left">
                  <History className="size-3.5 w-[22px] shrink-0 text-subtle" />
                  <span className="truncate text-[15px] text-white">{q}</span>
                  <ArrowUpLeft className="ml-auto size-3.5 shrink-0 text-subtle" strokeWidth={2.5} />
                </button>
                <button type="button" onClick={() => forgetQuery(q)} aria-label={`Remove “${q}”`} className="flex size-8 shrink-0 items-center justify-center rounded-full text-subtle hover:bg-white/[0.06] hover:text-foreground">
                  <X className="size-3.5" />
                </button>
              </li>
            ))}
          </ul>
        </section>
      )}
      {viewed.length > 0 && (
        <section aria-label="Recently viewed" className={queries.length ? "mt-[18px]" : undefined}>
          <Header title="Recently viewed" />
          <div className="fade-row -mx-4 overflow-x-auto px-4 [scrollbar-width:none] sm:-mx-8 sm:px-8 [&::-webkit-scrollbar]:hidden">
            <div className="flex gap-3">
              {viewed.map((item) => (
                <Link key={item.product.id} href={hrefOf(item)} onClick={() => onOpen(item)} className="w-[84px] shrink-0">
                  <ProductImage product={withEditionArt(item.product, item.printing)} size="sm" frame={item.product.kind === "sealed"} className="h-[116px] w-[84px]" />
                  <p className="mt-1.5 line-clamp-2 h-8 text-[12px] font-medium leading-4 text-white">{item.product.name}</p>
                  <p className="tabular mt-1 text-[12px] font-semibold text-muted">{money(item.market)}</p>
                </Link>
              ))}
            </div>
          </div>
        </section>
      )}
    </div>
  );
}

/** One result (the app's ResultRow): art, name, game · set · number, price and its age, "Owned ×N", and a lime +. */
function ResultRow({ item, ownedQty, onOpen }: { item: ExploreProduct; ownedQty: number; onOpen: () => void }) {
  const p = item.product;
  const href = hrefOf(item);
  const age = priceAge(item.priceUpdatedAt);
  return (
    <div className="flex items-center gap-3 py-2">
      <Link href={href} onClick={onOpen} className="flex min-w-0 flex-1 items-center gap-3">
        <ProductImage product={withEditionArt(p, item.printing)} size="sm" frame={p.kind === "sealed"} className="h-[89px] w-16 shrink-0" />
        <div className="min-w-0 flex-1 space-y-[3px]">
          <p className="line-clamp-2 text-[15px] font-medium leading-snug text-white">{p.name}</p>
          <p className="truncate text-[12px] text-muted">{[item.gameName ? shortGameName(item.gameName) : null, p.setName, p.number ? `#${p.number}` : null].filter(Boolean).join(" · ")}</p>
          <p className="tabular flex items-baseline gap-1.5 whitespace-nowrap">
            <span className="text-[14px] font-semibold text-white">{item.market === null ? "No price" : money(item.market)}</span>
            {age && <span className="text-[11px] text-subtle">{age}</span>}
            {ownedQty > 0 && (
              <span className="inline-flex items-center gap-0.5 text-[11px] font-semibold text-[var(--lime)]">
                <Check className="size-3" strokeWidth={3} /> {ownedLabel(ownedQty)}
              </span>
            )}
          </p>
        </div>
      </Link>
      {/* Adding happens on the card page ("Add to Collection"). */}
      <Link href={href} onClick={onOpen} aria-label={`Add ${p.name} to your collection`} className="flex size-[34px] shrink-0 items-center justify-center rounded-full bg-[var(--lime)] text-[#0b0b0c] transition-transform active:scale-90">
        <Plus className="size-4" strokeWidth={2.8} />
      </Link>
    </div>
  );
}

/** A still placeholder row while the catalog answers. */
function PlaceholderRow() {
  return (
    <div className="flex items-center gap-3 py-2 opacity-60" aria-hidden>
      <div className="h-[89px] w-16 shrink-0 rounded-[5px] bg-surface-2" />
      <div className="space-y-2">
        <div className="h-3 w-[180px] rounded-full bg-surface-2" />
        <div className="h-2.5 w-[120px] rounded-full bg-surface-2" />
      </div>
    </div>
  );
}
