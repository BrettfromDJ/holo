"use client";
/* eslint-disable @next/next/no-img-element -- brand logos come from the pricing source's CDN */

import { ChevronLeft } from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useMemo, useState } from "react";
import { SetTile, useExploreIndex } from "@/components/explore/explore-items";
import { Segmented } from "@/components/ui/segmented";
import { Skeleton } from "@/components/ui/skeleton";

type Show = "all" | "loaded";

/** One brand's sets, newest first, grouped by release year. */
export default function ExploreGamePage() {
  const { game: slug } = useParams<{ game: string }>();
  const index = useExploreIndex();
  const [show, setShow] = useState<Show>("all");

  const game = index.status === "ready" ? index.games.find((g) => g.slug === slug) : undefined;
  const years = useMemo(() => {
    if (index.status !== "ready") return [];
    const sets = index.sets.filter((s) => s.gameSlug === slug && (show === "all" || s.loaded));
    const groups = new Map<string, typeof sets>();
    for (const s of sets) {
      const y = s.releaseDate?.slice(0, 4) ?? "Undated";
      groups.set(y, [...(groups.get(y) ?? []), s]);
    }
    return [...groups.entries()].sort(([a], [b]) => (a === "Undated" ? 1 : b === "Undated" ? -1 : b.localeCompare(a)));
  }, [index, slug, show]);

  return (
    <div className="animate-fade-in">
      <Link href="/explore" className="mb-6 inline-flex items-center gap-1 text-[13px] text-muted hover:text-foreground">
        <ChevronLeft className="size-4" /> Explore
      </Link>

      {index.status === "loading" ? (
        <>
          <Skeleton className="h-20 w-64 rounded-2xl" />
          <div className="mt-8 grid grid-cols-2 gap-4 lg:grid-cols-4">
            {Array.from({ length: 8 }).map((_, i) => (
              <Skeleton key={i} className="aspect-[4/3] rounded-[var(--radius-card)]" />
            ))}
          </div>
        </>
      ) : index.status === "error" ? (
        <p className="py-20 text-center text-[14px] text-muted">{index.message}</p>
      ) : !game ? (
        <p className="py-20 text-center text-[14px] text-muted">This brand isn&apos;t in the catalog.</p>
      ) : (
        <>
          <header className="flex flex-wrap items-end justify-between gap-4">
            <div className="flex items-center gap-5">
              {game.logoUrl && <img src={game.logoUrl} alt="" className="h-14 w-auto max-w-[180px] object-contain sm:h-16" />}
              <div>
                <h1 className="text-[28px] font-semibold leading-tight tracking-[-0.02em]">{game.name}</h1>
                <p className="tabular mt-0.5 text-[13px] text-muted">
                  {game.sets} sets · {game.loadedSets} loaded
                </p>
              </div>
            </div>
            <Segmented
              ariaLabel="Show"
              size="sm"
              value={show}
              onChange={setShow}
              options={[
                { value: "all", label: "All sets" },
                { value: "loaded", label: "Loaded" },
              ]}
            />
          </header>

          {years.map(([year, sets]) => (
            <section key={year} className="mt-10" aria-label={year}>
              <div className="mb-4 flex items-baseline gap-3 border-b border-border pb-2">
                <h2 className="tabular text-[22px] font-semibold tracking-[-0.01em]">{year}</h2>
                <span className="text-[12px] text-subtle">
                  {sets.length} set{sets.length === 1 ? "" : "s"}
                </span>
              </div>
              <div className="grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-4">
                {sets.map((s) => (
                  <SetTile key={s.slug} set={s} />
                ))}
              </div>
            </section>
          ))}
        </>
      )}
    </div>
  );
}
