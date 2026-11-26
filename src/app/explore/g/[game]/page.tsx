"use client";
/* eslint-disable @next/next/no-img-element -- brand logos come from the pricing source's CDN */

import { ChevronLeft, Search } from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useMemo, useState } from "react";
import { logoTone, SetTile, useExploreIndex } from "@/components/explore/explore-items";
import { ExploreBackdrop, NextRelease } from "@/components/explore/landing";
import { Skeleton } from "@/components/ui/skeleton";
import { useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";

/** One game's sets, newest first, grouped by release year (the app's BrandView). */
export default function ExploreGamePage() {
  const { game: slug } = useParams<{ game: string }>();
  const index = useExploreIndex();
  const { today } = useStore();
  const [query, setQuery] = useState("");

  const game = index.status === "ready" ? index.games.find((g) => g.slug === slug) : undefined;
  const next = useMemo(() => {
    if (index.status !== "ready") return undefined;
    return index.sets.filter((s) => s.gameSlug === slug && s.releaseDate && s.releaseDate >= today).sort((a, b) => (a.releaseDate! < b.releaseDate! ? -1 : 1))[0];
  }, [index, slug, today]);
  const years = useMemo(() => {
    if (index.status !== "ready") return [];
    // Every word typed appears in the set's name (any case, accents ignored).
    const fold = (t: string) => t.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
    const words = fold(query).split(/\s+/).filter(Boolean);
    const sets = index.sets.filter((s) => s.gameSlug === slug && words.every((w) => fold(s.name).includes(w)));
    const groups = new Map<string, typeof sets>();
    for (const s of sets) {
      const y = s.releaseDate?.slice(0, 4) ?? "Undated";
      groups.set(y, [...(groups.get(y) ?? []), s]);
    }
    return [...groups.entries()]
      .sort(([a], [b]) => (a === "Undated" ? 1 : b === "Undated" ? -1 : b.localeCompare(a)))
      .map(([y, list]) => [y, list.sort((a, b) => ((b.releaseDate ?? "") > (a.releaseDate ?? "") ? 1 : -1))] as const);
  }, [index, slug, query]);

  return (
    <div className="relative animate-fade-in">
      <ExploreBackdrop />
      <Link href="/explore" className="mb-5 inline-flex items-center gap-1 text-[13px] text-muted hover:text-foreground">
        <ChevronLeft className="size-4" /> Explore
      </Link>

      {index.status === "loading" ? (
        <>
          <Skeleton className="h-16 w-64 rounded-2xl" />
          <div className="mt-8 grid grid-cols-2 gap-x-3.5 gap-y-5 lg:grid-cols-4">
            {Array.from({ length: 8 }).map((_, i) => (
              <Skeleton key={i} className="aspect-[3/2] rounded-2xl" />
            ))}
          </div>
        </>
      ) : index.status === "error" ? (
        <p className="py-20 text-center text-[14px] text-muted">{index.message}</p>
      ) : !game ? (
        <p className="py-20 text-center text-[14px] text-muted">This game isn&apos;t in the catalog.</p>
      ) : (
        <>
          <header className="flex items-center gap-4">
            <div className="flex h-16 w-[110px] shrink-0 items-center justify-center">
              {game.logoUrl ? (
                <img src={game.logoUrl} alt="" className={cn("max-h-full max-w-full object-contain drop-shadow-[0_8px_9px_rgba(0,0,0,0.5)]", logoTone(game))} />
              ) : (
                <span className="font-display text-[40px] leading-none text-[var(--lime)]">{game.name.slice(0, 1).toUpperCase()}</span>
              )}
            </div>
            <div className="min-w-0">
              <p className="font-mono text-[11px] uppercase tracking-[0.08em] text-subtle">Brand</p>
              <h1 className="mt-1.5 font-display text-[30px] leading-[1.02] tracking-[-0.035em] text-balance">{game.name}</h1>
            </div>
          </header>
          {next && (
            <div className="mt-4">
              <NextRelease set={next} />
            </div>
          )}

          <label className="glass mt-6 flex h-12 items-center gap-2.5 rounded-full px-4">
            <Search className="size-4 text-muted" strokeWidth={2.5} aria-hidden />
            <input
              type="search"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder={`Search ${game.name} sets`}
              aria-label={`Search ${game.name} sets`}
              className="h-full w-full bg-transparent text-[16px] text-foreground outline-none placeholder:text-subtle"
            />
          </label>
          {years.length === 0 && query.trim() && <p className="mt-6 text-[14px] text-muted">No sets match &ldquo;{query.trim()}&rdquo;.</p>}

          {years.map(([year, sets]) => (
            <section key={year} className="mt-8" aria-label={year}>
              <div className="mb-3.5 flex items-baseline gap-2.5">
                <h2 className="tabular font-display text-[24px] leading-none tracking-[-0.03em]">{year}</h2>
                <span className="font-mono text-[11px] uppercase tracking-[0.08em] text-subtle">
                  {sets.length} set{sets.length === 1 ? "" : "s"}
                </span>
              </div>
              <div className="grid grid-cols-2 gap-x-3.5 gap-y-5 lg:grid-cols-4">
                {sets.map((s) => (
                  <SetTile key={s.slug} set={s} upcoming={Boolean(s.releaseDate && s.releaseDate >= today)} />
                ))}
              </div>
            </section>
          ))}
        </>
      )}
    </div>
  );
}
