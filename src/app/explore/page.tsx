"use client";

import { FlipGrid, FlipItem } from "@/components/motion/flip-grid";
import { Compass, Loader2, Search, X } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import { ProductTile, useExploreIndex, useOwnedIds, useOwnedQuantities } from "@/components/explore/explore-items";
import { BrandCard, CatalogHero, ExploreBackdrop, LandingHeading, SetCarousel } from "@/components/explore/landing";
import { PageHeader } from "@/components/shell/page-header";
import { Skeleton } from "@/components/ui/skeleton";
import { SearchFilterBar } from "@/components/explore/search-filters";
import { applyFilters, groupByKind, NO_FILTERS, type SearchFilters } from "@/lib/explore/filters";
import { useCatalogSearch } from "@/lib/explore/use-catalog-search";
import { useStore } from "@/lib/store/collection-store";

export default function ExplorePage() {
  const index = useExploreIndex();
  const games = index.status === "ready" ? index.games : [];
  const [query, setQuery] = useState("");
  const searchInput = useRef<HTMLInputElement>(null);
  const results = useCatalogSearch(query);
  const owned = useOwnedIds();
  const ownedQty = useOwnedQuantities();
  const { today, data } = useStore();
  const [filters, setFilters] = useState<SearchFilters>(NO_FILTERS);
  const watched = useMemo(() => new Set(data.watchlist.map((w) => w.productId)), [data.watchlist]);
  const shown = useMemo(() => (results?.status === "ready" ? applyFilters(results.data, filters, { owned, watched }) : []), [results, filters, owned, watched]);
  // Cards and sealed under their own headings, unless the Type filter already picked one.
  const groups = useMemo(() => (filters.type === "all" ? groupByKind(shown) : [{ kind: filters.type, title: "", items: shown }]), [shown, filters.type]);

  // Arriving from the home search ("/explore?q=…") starts with that query.
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const q = params.get("q");
    if (q) setQuery(q);
    // From the phone tab bar's search button: straight into typing.
    if (params.get("search") === "1") searchInput.current?.focus();
    const focus = () => searchInput.current?.focus();
    window.addEventListener("focus-explore-search", focus);
    return () => window.removeEventListener("focus-explore-search", focus);
  }, []);

  // Sets still to come (soonest first) and already out (newest first), as in the app.
  const upcoming = index.status === "ready" ? index.sets.filter((s) => s.releaseDate && s.releaseDate >= today).sort((a, b) => (a.releaseDate! < b.releaseDate! ? -1 : 1)) : [];
  const recent = index.status === "ready" ? index.sets.filter((s) => s.releaseDate && s.releaseDate < today).sort((a, b) => (a.releaseDate! > b.releaseDate! ? -1 : 1)) : [];

  return (
    <div className="relative animate-fade-in">
      <ExploreBackdrop />
      <PageHeader title="Explore" subtitle="Every brand, set, sealed product and single" />

      <div className="sticky top-[calc(3.5rem+env(safe-area-inset-top))] z-20 -mx-4 bg-background/90 px-4 py-3 backdrop-blur-xl sm:-mx-8 sm:px-8 lg:top-0">
        <div className="relative">
          <Search className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-subtle" />
          <input
            ref={searchInput}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search cards and sealed across every brand — e.g. “umbreon”, “151 etb”"
            aria-label="Search the catalog"
            className="h-11 w-full rounded-full bg-surface-2 pl-10 pr-10 text-[14px] outline-none placeholder:text-subtle focus:bg-surface-3"
          />
          {query && (
            <button onClick={() => setQuery("")} aria-label="Clear search" className="absolute right-3.5 top-1/2 -translate-y-1/2 text-subtle hover:text-foreground">
              <X className="size-4" />
            </button>
          )}
        </div>
      </div>

      {results ? (
        <section className="mt-4" aria-label="Search results">
          {results.status === "loading" ? (
            <p className="flex items-center gap-2 py-10 text-[14px] text-muted">
              <Loader2 className="size-4 animate-spin" /> Searching the catalog…
            </p>
          ) : results.status === "error" ? (
            <p className="py-10 text-[14px] text-down">{results.message}</p>
          ) : !results.data.length ? (
            <div className="py-16 text-center">
              <p className="font-medium">Nothing in the catalog yet</p>
              <p className="mt-1 text-sm text-muted">The catalog fills in a few sets a day. Try another search, or add it from “Add to Collection”.</p>
            </div>
          ) : (
            <>
              {results.fuzzy && <p className="mb-3 text-[14px] text-muted">Showing close matches for “{query.trim()}”</p>}
              <SearchFilterBar items={results.data} filters={filters} onChange={setFilters} />
              <p className="tabular mt-3 text-[12px] text-subtle">
                {shown.length === results.data.length ? `${results.data.length} result${results.data.length === 1 ? "" : "s"}` : `${shown.length} of ${results.data.length} results`}
              </p>
              {shown.length ? (
                groups.map((g) => (
                  <div key={g.kind} className={g.title ? "mt-6" : undefined}>
                    {g.title && (
                      <h2 className="flex items-baseline gap-2 font-display text-[18px] leading-none tracking-tight">
                        {g.title} <span className="tabular font-mono text-[12px] font-normal text-subtle">{g.items.length}</span>
                      </h2>
                    )}
                    <FlipGrid className="mt-4 grid grid-cols-2 gap-x-5 gap-y-10 sm:grid-cols-3 lg:grid-cols-4">
                      {g.items.map((item, i) => (
                        <FlipItem key={item.product.id} flipKey={item.product.id} index={i}>
                          <ProductTile item={item} owned={owned.has(item.product.id)} ownedQty={ownedQty.get(item.product.id)} showBrand />
                        </FlipItem>
                      ))}
                    </FlipGrid>
                  </div>
                ))
              ) : (
                <div className="py-16 text-center">
                  <p className="font-medium">No results match these filters</p>
                  <button type="button" onClick={() => setFilters({ ...NO_FILTERS, sort: filters.sort })} className="mt-2 text-sm font-medium text-muted underline underline-offset-4 hover:text-foreground">
                    Clear filters
                  </button>
                </div>
              )}
            </>
          )}
        </section>
      ) : index.status === "loading" ? (
        <div className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="aspect-[16/11] rounded-[var(--radius-card)]" />
          ))}
        </div>
      ) : index.status === "error" ? (
        <EmptyCatalog title="Explore isn't set up yet" body={index.message} />
      ) : !index.games.length ? (
        <EmptyCatalog title="The catalog is empty for now" body="It fills in automatically each day. To start it now, run the “sync-catalog” cron job." />
      ) : (
        <>
          {/* The app's Explore: the catalog's size and the next release, sets coming soon and just
              released as rows of art, then the brands. */}
          <div className="mt-4">
            <CatalogHero index={index} next={upcoming[0]} />
          </div>
          {upcoming.length > 1 && (
            <section aria-label="Coming soon" className="mt-10">
              <LandingHeading title="Coming soon" subtitle="New sets on the way" href="/explore/releases" linkLabel="Calendar" />
              <SetCarousel sets={upcoming.slice(1, 13)} upcoming />
            </section>
          )}
          {recent.length > 0 && (
            <section aria-label="Just released" className="mt-10">
              <LandingHeading title="Just released" subtitle="The newest sets in the catalog" />
              <SetCarousel sets={recent.slice(0, 12)} upcoming={false} />
            </section>
          )}
          <section aria-label="Brands" className="mt-10">
            <LandingHeading title="Brands" subtitle="Every game in the catalog" />
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
              {games.map((g, i) => (
                <BrandCard key={g.slug} game={g} i={i} />
              ))}
            </div>
          </section>
        </>
      )}
    </div>
  );
}

function EmptyCatalog({ title, body }: { title: string; body: string }) {
  return (
    <div className="flex flex-col items-center py-24 text-center">
      <Compass className="size-10 text-subtle" strokeWidth={1.5} />
      <p className="mt-4 font-medium">{title}</p>
      <p className="mt-1 max-w-md text-sm text-muted">{body}</p>
    </div>
  );
}
