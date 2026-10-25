"use client";

import { Compass, Loader2, Search, X } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { ProductSheet, ProductTile, SetTile, useOwnedIds } from "@/components/explore/explore-items";
import { PageHeader } from "@/components/shell/page-header";
import { Segmented } from "@/components/ui/segmented";
import { Skeleton } from "@/components/ui/skeleton";
import type { ExploreProduct, ExploreSet } from "@/lib/explore/types";
import { relativeTime } from "@/lib/format";

type Load<T> = { status: "loading" } | { status: "error"; message: string } | { status: "ready"; data: T };

async function getJSON<T>(url: string): Promise<T> {
  const res = await fetch(url);
  const body = await res.json().catch(() => null);
  if (!res.ok) throw new Error(body?.error?.message ?? "Couldn't load the catalog.");
  return body as T;
}

export default function ExplorePage() {
  const [sets, setSets] = useState<Load<ExploreSet[]>>({ status: "loading" });
  const [game, setGame] = useState<string>("");
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Load<ExploreProduct[]> | null>(null);
  const [open, setOpen] = useState<ExploreProduct | null>(null);
  const owned = useOwnedIds();

  useEffect(() => {
    getJSON<{ sets: ExploreSet[] }>("/api/explore").then(
      (b) => setSets({ status: "ready", data: b.sets }),
      (e: Error) => setSets({ status: "error", message: e.message }),
    );
  }, []);

  // Debounced catalog search — served from Supabase, never the TCG API.
  useEffect(() => {
    const q = query.trim();
    if (q.length < 2) return setResults(null);
    setResults({ status: "loading" });
    const t = window.setTimeout(() => {
      getJSON<{ products: ExploreProduct[] }>(`/api/explore/search?q=${encodeURIComponent(q)}`).then(
        (b) => setResults({ status: "ready", data: b.products }),
        (e: Error) => setResults({ status: "error", message: e.message }),
      );
    }, 300);
    return () => window.clearTimeout(t);
  }, [query]);

  const games = useMemo(() => {
    if (sets.status !== "ready") return [];
    const map = new Map<string, string>();
    for (const s of sets.data) if (!map.has(s.gameSlug)) map.set(s.gameSlug, s.gameName);
    // English Pokémon first.
    return [...map.entries()].sort(([a], [b]) => (a === "pokemon" ? -1 : b === "pokemon" ? 1 : a.localeCompare(b)));
  }, [sets]);
  const activeGame = game || games[0]?.[0] || "";
  const shown = sets.status === "ready" ? sets.data.filter((s) => s.gameSlug === activeGame) : [];
  const loaded = sets.status === "ready" ? sets.data.filter((s) => s.loaded) : [];
  const lastSync = loaded.reduce<string | null>((m, s) => (s.syncedAt && (!m || s.syncedAt > m) ? s.syncedAt : m), null);

  return (
    <div className="animate-fade-in">
      <PageHeader title="Explore" subtitle="Every set, sealed product and single — browse without touching your API budget" />

      <div className="sticky top-14 z-20 -mx-4 bg-background/90 px-4 py-3 backdrop-blur-xl sm:-mx-8 sm:px-8 lg:top-0">
        <div className="relative">
          <Search className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-subtle" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search sets, cards and sealed — e.g. “umbreon”, “151 etb”"
            aria-label="Search the catalog"
            className="h-11 w-full rounded-full bg-surface-2 pl-10 pr-10 text-[14px] outline-none placeholder:text-subtle focus:bg-surface-3"
          />
          {query && (
            <button onClick={() => setQuery("")} aria-label="Clear search" className="absolute right-3.5 top-1/2 -translate-y-1/2 text-subtle hover:text-foreground">
              <X className="size-4" />
            </button>
          )}
        </div>
        {!results && games.length > 1 && (
          <div className="mt-3">
            <Segmented ariaLabel="Game" size="sm" value={activeGame} onChange={setGame} options={games.map(([slug, name]) => ({ value: slug, label: name }))} />
          </div>
        )}
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
                <ProductTile key={item.product.id} item={item} owned={owned.has(item.product.id)} onOpen={() => setOpen(item)} />
              ))}
            </div>
          )}
        </section>
      ) : sets.status === "loading" ? (
        <div className="mt-6 grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4">
          {Array.from({ length: 8 }).map((_, i) => (
            <Skeleton key={i} className="aspect-[16/9] rounded-2xl" />
          ))}
        </div>
      ) : sets.status === "error" ? (
        <div className="flex flex-col items-center py-24 text-center">
          <Compass className="size-10 text-subtle" strokeWidth={1.5} />
          <p className="mt-4 font-medium">Explore isn&apos;t set up yet</p>
          <p className="mt-1 max-w-md text-sm text-muted">{sets.message}</p>
        </div>
      ) : !sets.data.length ? (
        <div className="flex flex-col items-center py-24 text-center">
          <Compass className="size-10 text-subtle" strokeWidth={1.5} />
          <p className="mt-4 font-medium">The catalog is empty for now</p>
          <p className="mt-1 max-w-md text-sm text-muted">It fills in automatically each day. To start it now, run the “sync-catalog” cron job in Vercel.</p>
        </div>
      ) : (
        <>
          <p className="mt-3 text-[12px] text-subtle">
            {loaded.length} of {sets.data.length} sets loaded{lastSync ? ` · last update ${relativeTime(lastSync)}` : ""} · more sets and fresher prices every day
          </p>
          <div className="mt-5 grid grid-cols-2 gap-x-4 gap-y-7 sm:grid-cols-3 lg:grid-cols-4">
            {shown.map((s, i) => (
              <div key={s.slug} className="animate-rise" style={{ animationDelay: `${Math.min(i, 16) * 30}ms` }}>
                <SetTile set={s} />
              </div>
            ))}
          </div>
        </>
      )}

      <ProductSheet item={open} onClose={() => setOpen(null)} />
    </div>
  );
}
