"use client";

import { Compass } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useMemo } from "react";
import { useExploreIndex } from "@/components/explore/explore-items";
import { BrandCard, CatalogHero, ExploreBackdrop, LandingHeading, SearchFieldLink, SetCarousel } from "@/components/explore/landing";
import { Skeleton } from "@/components/ui/skeleton";
import { orderGames } from "@/lib/games";
import { useStore } from "@/lib/store/collection-store";

/**
 * Explore's landing, the app's ExploreView: the search box (opens /search), then Games in the
 * owner's order, the next release, Coming soon (with Calendar) and Just released. No subtitles.
 */
export function ExploreLanding() {
  const index = useExploreIndex();
  const router = useRouter();
  const { today } = useStore();
  const games = useMemo(() => (index.status === "ready" ? orderGames(index.games) : []), [index]);

  // The phone tab bar's search button, pressed while already on Explore.
  useEffect(() => {
    const open = () => router.push("/search");
    window.addEventListener("focus-explore-search", open);
    return () => window.removeEventListener("focus-explore-search", open);
  }, [router]);

  // Sets still to come (soonest first) and already out (newest first), as in the app.
  const { upcoming, recent } = useMemo(() => {
    if (index.status !== "ready") return { upcoming: [], recent: [] };
    return {
      upcoming: index.sets.filter((s) => s.releaseDate && s.releaseDate >= today).sort((a, b) => (a.releaseDate! < b.releaseDate! ? -1 : 1)),
      recent: index.sets.filter((s) => s.releaseDate && s.releaseDate < today).sort((a, b) => (a.releaseDate! > b.releaseDate! ? -1 : 1)),
    };
  }, [index, today]);

  return (
    <div className="relative animate-fade-in">
      <ExploreBackdrop />
      <h1 className="pt-2 font-display text-[30px] leading-none tracking-[-0.035em] sm:text-[36px]">Explore</h1>
      <SearchFieldLink className="mt-5" />

      {index.status === "loading" ? (
        <div className="mt-8 space-y-4" aria-hidden>
          <Skeleton className="h-5 w-24 rounded-md" />
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
            {Array.from({ length: 4 }).map((_, i) => (
              <Skeleton key={i} className="h-[124px] rounded-[20px]" />
            ))}
          </div>
        </div>
      ) : index.status === "error" ? (
        <EmptyCatalog title="Explore isn't set up yet" body={index.message} />
      ) : !index.games.length ? (
        <EmptyCatalog title="The catalog is empty for now" body="It fills in automatically each day. To start it now, run the “sync-catalog” cron job." />
      ) : (
        <>
          <section aria-label="Games" className="mt-6">
            <LandingHeading title="Games" />
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
              {games.map((g) => (
                <BrandCard key={g.slug} game={g} />
              ))}
            </div>
          </section>
          {upcoming[0] && (
            <div className="mt-10">
              <CatalogHero next={upcoming[0]} />
            </div>
          )}
          {upcoming.length > 1 && (
            <section aria-label="Coming soon" className="mt-10">
              <LandingHeading title="Coming soon" href="/explore/releases" linkLabel="Calendar" />
              <SetCarousel sets={upcoming.slice(1, 13)} upcoming />
            </section>
          )}
          {recent.length > 0 && (
            <section aria-label="Just released" className="mt-10">
              <LandingHeading title="Just released" />
              <SetCarousel sets={recent.slice(0, 12)} upcoming={false} />
            </section>
          )}
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
