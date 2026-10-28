"use client";

import { ArrowRight, Compass, Loader2, Search, X } from "lucide-react";
import Link from "next/link";
import { useEffect, useState } from "react";
import { GameTile, ProductTile, useExploreIndex, useOwnedIds } from "@/components/explore/explore-items";
import { ReleaseRow } from "@/components/explore/release-items";
import { PageHeader } from "@/components/shell/page-header";
import { Skeleton } from "@/components/ui/skeleton";
import type { ExploreProduct } from "@/lib/explore/types";
import { relativeTime } from "@/lib/format";
import { useStore } from "@/lib/store/collection-store";

type Load<T> = { status: "loading" } | { status: "error"; message: string } | { status: "ready"; data: T };

export default function ExplorePage() {
  const index = useExploreIndex();
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Load<ExploreProduct[]> | null>(null);
  const owned = useOwnedIds();
  const { today } = useStore();

  // Debounced catalog search — served from Supabase, never the TCG API.
  useEffect(() => {
    const q = query.trim();
    if (q.length < 2) return setResults(null);
    setResults({ status: "loading" });
    const t = window.setTimeout(() => {
      fetch(`/api/explore/search?q=${encodeURIComponent(q)}`)
        .then(async (res) => {
          const body = await res.json().catch(() => null);
          if (!res.ok) throw new Error(body?.error?.message ?? "Search failed.");
          return body.products as ExploreProduct[];
        })
        .then(
          (data) => setResults({ status: "ready", data }),
          (e: Error) => setResults({ status: "error", message: e.message }),
        );
    }, 300);
    return () => window.clearTimeout(t);
  }, [query]);

  const loaded = index.status === "ready" ? index.sets.filter((s) => s.loaded) : [];
  const upcoming = index.status === "ready" ? index.sets.filter((s) => s.releaseDate && s.releaseDate >= today).sort((a, b) => (a.releaseDate! < b.releaseDate! ? -1 : 1)).slice(0, 4) : [];
  const lastSync = loaded.reduce<string | null>((m, s) => (s.syncedAt && (!m || s.syncedAt > m) ? s.syncedAt : m), null);

  return (
    <div className="animate-fade-in">
      <PageHeader title="Explore" subtitle="Every brand, set, sealed product and single" />

      <div className="sticky top-14 z-20 -mx-4 bg-background/90 px-4 py-3 backdrop-blur-xl sm:-mx-8 sm:px-8 lg:top-0">
        <div className="relative">
          <Search className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-subtle" />
          <input
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
            <div className="grid grid-cols-2 gap-x-4 gap-y-7 sm:grid-cols-3 lg:grid-cols-5">
              {results.data.map((item) => (
                <ProductTile key={item.product.id} item={item} owned={owned.has(item.product.id)} showBrand />
              ))}
            </div>
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
        {upcoming.length > 0 && (
          <section aria-label="Coming soon" className="mt-4">
            <div className="mb-2 flex items-baseline justify-between gap-3">
              <h2 className="text-[13px] font-medium font-mono uppercase tracking-[0.06em] text-muted">Coming soon</h2>
              <Link href="/explore/releases" className="flex items-center gap-1 text-[13px] font-medium text-muted hover:text-foreground">
                Release calendar <ArrowRight className="size-3.5" />
              </Link>
            </div>
            <div className="grid gap-x-6 sm:grid-cols-2">
              {upcoming.map((s) => (
                <ReleaseRow key={s.slug} set={s} />
              ))}
            </div>
          </section>
        )}
        <section aria-label="Brands" className="mt-8">
          <div className="mb-4 flex items-baseline gap-3">
            <h2 className="text-[13px] font-medium font-mono uppercase tracking-[0.06em] text-muted">Brands</h2>
            <span className="text-[12px] text-subtle">
              {loaded.length} of {index.sets.length} sets loaded{lastSync ? ` · updated ${relativeTime(lastSync)}` : ""}
            </span>
          </div>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {index.games.map((g, i) => (
              <div key={g.slug} className="animate-rise" style={{ animationDelay: `${i * 60}ms` }}>
                <GameTile game={g} />
              </div>
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
