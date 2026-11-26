"use client";

import { Bell, Menu } from "lucide-react";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useExploreIndex } from "@/components/explore/explore-items";
import { CatalogHero, SetCarousel } from "@/components/explore/landing";
import { gridPattern } from "@/components/master-sets/master-set-items";
import { HomeSearch } from "@/components/overview/home-search";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Skeleton } from "@/components/ui/skeleton";
import { isOversized } from "@/lib/explore/movers";
import type { Theme } from "@/lib/explore/themes";
import type { ExploreSet } from "@/lib/explore/types";
import { cleanThemes, dayNumber, filteredThemes, fitsFilter, HOME_FILTERS, pickThemes, readRecentThemes, rememberThemes, uniqueHits, type HomeFilter, type ThemePick } from "@/lib/home/pick-themes";
import { useStore } from "@/lib/store/collection-store";
import { useShelves } from "@/lib/store/shelves";
import { cn } from "@/lib/utils";
import { CardOfTheDay, ChipTabs, HotColdTile, HotSealedRow, PlaceholderRow, PosterRow, RowTitle, SeeAll, SetShowcase, ThemeRow, TopTenRow, type HomeHit } from "./home-pieces";

/**
 * Home: what's happening across the hobby, not your collection (the app's `MarketHomeView`).
 * Card of the day, Collection of the Day, Heating up / Cooling off, Top 10, the newest set's chase
 * cards, hot sealed, sets just out and coming, with themed collections between them and your
 * lists last. The tabs under the search cut every row to one era.
 */

/** A new mix each page load (the same while the page stays open). */
const launchSeed = Math.floor(Math.random() * 2 ** 31);

let themesRequest: Promise<Theme[]> | null = null;
function fetchThemes(): Promise<Theme[]> {
  themesRequest ??= fetch("/api/themes")
    .then((r) => (r.ok ? r.json() : { themes: [] }))
    .then((b: { themes?: Theme[] }) => cleanThemes(b.themes ?? []))
    .catch(() => {
      themesRequest = null;
      return [];
    });
  return themesRequest;
}

/** Home's themed collections: all of them, plus Collection of the Day and this visit's mix. */
function useThemes() {
  const [state, setState] = useState<{ loaded: boolean; all: Theme[]; pick: ThemePick }>({ loaded: false, all: [], pick: { daily: null, shown: [] } });
  useEffect(() => {
    let live = true;
    fetchThemes().then((all) => {
      if (!live) return;
      const pick = pickThemes(all, { day: dayNumber(), seed: launchSeed, recent: readRecentThemes() });
      if (pick.shown.length) rememberThemes(pick.shown.map((t) => t.id));
      setState({ loaded: true, all, pick });
    });
    return () => {
      live = false;
    };
  }, []);
  return state;
}

/** The newest released set's ten most valuable singles. */
function useChase(set: ExploreSet | undefined) {
  const [chase, setChase] = useState<{ set: ExploreSet; hits: HomeHit[] } | null>(null);
  const slug = set?.slug;
  useEffect(() => {
    if (!slug) return;
    let live = true;
    fetch(`/api/explore/sets/${encodeURIComponent(slug)}`)
      .then((r) => (r.ok ? r.json() : null))
      .then((body: { set: ExploreSet; products: HomeHit[] } | null) => {
        if (!live || !body?.set) return;
        const singles = (body.products ?? []).filter((p) => p.product.kind === "single" && p.market !== null && !isOversized(p.product));
        singles.sort((a, b) => (b.market ?? 0) - (a.market ?? 0));
        setChase({ set: body.set, hits: singles.slice(0, 10) });
      })
      .catch(() => {});
    return () => {
      live = false;
    };
  }, [slug]);
  return chase;
}

export function MarketHome() {
  const index = useExploreIndex();
  const { today } = useStore();
  const themes = useThemes();
  const [filter, setFilter] = useState<HomeFilter>("all");
  const ready = index.status === "ready" ? index : null;

  const { upcoming, recent } = useMemo(() => {
    const sets = ready?.sets ?? [];
    return {
      upcoming: sets.filter((s) => s.releaseDate && s.releaseDate >= today).sort((a, b) => (a.releaseDate! < b.releaseDate! ? -1 : 1)),
      recent: sets.filter((s) => s.releaseDate && s.releaseDate < today).sort((a, b) => (a.releaseDate! > b.releaseDate! ? -1 : 1)),
    };
  }, [ready, today]);
  const chase = useChase(recent.find((s) => s.loaded) ?? recent[0]);

  return (
    <div className="relative animate-fade-in">
      <HomeBackdrop />
      <HomeHeader />
      <HomeSearch className="mt-4" />
      <div className="mt-4">
        <ChipTabs label="Show cards from" options={HOME_FILTERS} value={filter} onChange={setFilter} />
      </div>
      <div className="mt-6 space-y-8">
        {index.status === "loading" ? (
          <HomeLoading />
        ) : index.status === "error" ? (
          <p className="py-16 text-center text-[15px] text-muted">{index.message}</p>
        ) : filter === "all" ? (
          <AllSections index={index} themes={themes} upcoming={upcoming} recent={recent} chase={chase} />
        ) : (
          <FilteredSections index={index} themes={themes} filter={filter} />
        )}
      </div>
    </div>
  );
}

type Index = Extract<ReturnType<typeof useExploreIndex>, { status: "ready" }>;
type ThemesState = ReturnType<typeof useThemes>;

const visible = (hits: HomeHit[]) => hits.filter((h) => !isOversized(h.product));

/** Card of the day with, beside it on wide screens, Heating up and Cooling off; Collection of the Day under. */
function Highlights({ star, kind, risers, drops, daily }: { star?: HomeHit; kind: "day" | "week" | { topPull: string }; risers: HomeHit[]; drops: HomeHit[]; daily?: Theme | null }) {
  const tiles = risers.length > 0 || drops.length > 0;
  return (
    // Phone: Card of the day, Collection of the Day, then the two tiles (the app's order). Wide:
    // the tiles sit beside Card of the day and Collection of the Day runs under both.
    <div className="flex flex-col gap-8 lg:grid lg:grid-cols-[minmax(0,1.15fr)_minmax(0,1fr)] lg:gap-x-6">
      {star && (
        <div className="lg:col-start-1 lg:row-start-1">
          <CardOfTheDay hit={star} kind={kind} />
        </div>
      )}
      {daily && (
        <div className="min-w-0 lg:col-span-2 lg:row-start-2">
          <ThemeRow label="Today's discovery" title={daily.title} hits={daily.hits} />
        </div>
      )}
      {tiles && (
        <div className={cn("grid grid-cols-2 gap-2.5 lg:row-start-1 lg:content-start", star ? "lg:col-start-2" : "lg:col-span-2")}>
          {risers.length > 0 && <HotColdTile hits={risers} hot />}
          {drops.length > 0 && <HotColdTile hits={drops} hot={false} />}
        </div>
      )}
    </div>
  );
}

/** Some of this visit's collections, by position (still rows hold their place while they load). */
function ThemeRows({ themes, list, from, to }: { themes: ThemesState; list: Theme[]; from: number; to?: number }) {
  if (!themes.loaded && from === 0)
    return (
      <>
        <PlaceholderRow />
        <PlaceholderRow />
      </>
    );
  return (
    <>
      {list.slice(from, to).map((t) => (
        <ThemeRow key={t.id} title={t.title} fresh={t.fresh} hits={t.hits} />
      ))}
    </>
  );
}

function AllSections({ index, themes, upcoming, recent, chase }: { index: Index; themes: ThemesState; upcoming: ExploreSet[]; recent: ExploreSet[]; chase: { set: ExploreSet; hits: HomeHit[] } | null }) {
  const trending = visible(index.trending);
  const drops = visible(index.drops);
  const todayTop = visible(index.today)[0];
  const star = todayTop ?? trending[0] ?? chase?.hits[0];
  const kind = todayTop ? "day" : trending[0] ? "week" : { topPull: chase?.set.name ?? "" };
  const risers = (todayTop ? trending : trending.slice(1)).slice(0, 5);
  const shown = themes.pick.shown;
  const top = trending.slice(0, 10);
  const hot = visible(index.hotSealed).slice(0, 10);
  return (
    <>
      <Highlights star={star} kind={kind} risers={risers} drops={drops.slice(0, 5)} daily={themes.pick.daily} />
      <ThemeRows themes={themes} list={shown} from={0} to={3} />
      {trending.length > 2 && (
        <section>
          <RowTitle title="Top 10 this week" />
          <TopTenRow hits={top} />
        </section>
      )}
      <ThemeRows themes={themes} list={shown} from={3} to={8} />
      {upcoming[0] && <CatalogHero next={upcoming[0]} />}
      {chase && chase.hits.length > 0 && (
        <div className="sm:max-w-xl">
          <SetShowcase set={chase.set} hits={chase.hits.slice(0, 5)} />
        </div>
      )}
      {hot.length > 0 && (
        <section>
          <RowTitle title="Hot sealed" />
          <HotSealedRow hits={hot} />
        </section>
      )}
      <ThemeRows themes={themes} list={shown} from={8} to={11} />
      {recent.length > 0 && (
        <section>
          <RowTitle title="Just released" />
          <SetCarousel sets={recent.slice(0, 10)} upcoming={false} />
        </section>
      )}
      {upcoming.length > 1 && (
        <section>
          <RowTitle title="Coming soon" link={<SeeAll href="/explore/releases" label="Calendar" />} />
          <SetCarousel sets={upcoming.slice(1, 11)} upcoming />
        </section>
      )}
      <ThemeRows themes={themes} list={shown} from={11} />
      <ListRows />
    </>
  );
}

function FilteredSections({ index, themes, filter }: { index: Index; themes: ThemesState; filter: HomeFilter }) {
  const fits = (h: HomeHit) => fitsFilter(filter, h);
  const today = visible(index.today).filter(fits);
  const week = uniqueHits(visible([...index.trending, ...index.hotSealed]).filter(fits));
  const drops = visible(index.drops).filter(fits);
  const top = [...week].sort((a, b) => (b.change7dPct ?? 0) - (a.change7dPct ?? 0)).slice(0, 10);
  const rows = themes.loaded ? filteredThemes(themes.pick, themes.all, filter) : [];
  const star = today[0] ?? top[0];
  const risers = (today.length ? top : top.slice(1)).slice(0, 5);
  return (
    <>
      <Highlights star={star} kind={today[0] ? "day" : "week"} risers={risers} drops={drops.slice(0, 5)} />
      <ThemeRows themes={themes} list={rows} from={0} to={2} />
      {top.length > 2 && (
        <section>
          <RowTitle title="Top 10 this week" />
          <TopTenRow hits={top} />
        </section>
      )}
      <ThemeRows themes={themes} list={rows} from={2} />
      {!star && !top.length && themes.loaded && !rows.length && <p className="py-10 text-center text-[15px] text-muted">Nothing to show here yet.</p>}
    </>
  );
}

/** Your lists, last, as rows like the collections (cards from your own records). */
function ListRows() {
  const { shelves } = useShelves();
  const { data, mode } = useStore();
  const market = useMemo(() => {
    const out = new Map<string, number>();
    for (const p of Object.values(data.prices)) if (p.market !== null && !out.has(p.productId)) out.set(p.productId, p.market);
    return out;
  }, [data.prices]);
  if (mode === "demo") return null;
  return (
    <>
      {shelves.map((list) => {
        const hits: HomeHit[] = list.productIds.flatMap((id) => {
          const product = data.products[id];
          return product ? [{ product, printing: null, market: market.get(id) ?? null, priceUpdatedAt: null }] : [];
        });
        if (!hits.length) return null;
        return (
          <section key={list.id}>
            <RowTitle title={list.name} />
            <PosterRow hits={hits} />
          </section>
        );
      })}
    </>
  );
}

/** "Home" big on the left; the watchlist bell and the places menu on the right. */
function HomeHeader() {
  const places: { href: string; label: string }[][] = [
    [
      { href: "/collection", label: "Collection" },
      { href: "/explore", label: "Explore" },
      { href: "/deal", label: "Deal" },
    ],
    [
      { href: "/analytics", label: "Analytics" },
      { href: "/grading", label: "Grading" },
      { href: "/master-sets", label: "Master sets" },
      { href: "/activity", label: "Activity" },
    ],
    [
      { href: "/watchlist", label: "Watchlist" },
      { href: "/wishlist", label: "Wishlist" },
      { href: "/settings", label: "Settings" },
    ],
  ];
  return (
    <header className="flex items-center gap-1">
      <h1 className="font-display text-[32px] leading-none tracking-[-0.03em]">Home</h1>
      <span className="flex-1" />
      <Link href="/watchlist" aria-label="Watchlist and price alerts" className="flex size-11 items-center justify-center rounded-full text-white hover:bg-white/[0.06]">
        <Bell className="size-5" />
      </Link>
      <DropdownMenu>
        <DropdownMenuTrigger aria-label="Menu" className="flex size-11 items-center justify-center rounded-full text-white outline-none hover:bg-white/[0.06] focus-visible:ring-2 focus-visible:ring-ring">
          <Menu className="size-5" />
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="min-w-[12rem]">
          {places.map((group, g) => (
            <div key={g}>
              {g > 0 && <DropdownMenuSeparator />}
              {group.map((p) => (
                <DropdownMenuItem key={p.href} asChild>
                  <Link href={p.href}>{p.label}</Link>
                </DropdownMenuItem>
              ))}
            </div>
          ))}
        </DropdownMenuContent>
      </DropdownMenu>
    </header>
  );
}

/** The faint grid behind the top, fading out down the page (quieter than Explore's, no glows). */
function HomeBackdrop() {
  return (
    <div aria-hidden className="pointer-events-none absolute inset-x-0 -top-24 -z-10 h-[420px] [mask-image:linear-gradient(to_bottom,black,transparent)]">
      <div className="absolute inset-0" style={gridPattern(28, "rgb(255 255 255 / 0.05)")} />
    </div>
  );
}

/** Home before its lists arrive: still shapes in Home's layout. */
function HomeLoading() {
  return (
    <div aria-label="Loading Home" className="space-y-8">
      <div className="flex flex-col gap-8 lg:grid lg:grid-cols-[minmax(0,1.15fr)_minmax(0,1fr)] lg:gap-x-6">
        <Skeleton className="h-[520px] rounded-[24px]" />
        <div className="grid grid-cols-2 content-start gap-2.5">
          <Skeleton className="h-[240px] rounded-[22px]" />
          <Skeleton className="h-[240px] rounded-[22px]" />
        </div>
      </div>
      <PlaceholderRow />
      <PlaceholderRow />
    </div>
  );
}
