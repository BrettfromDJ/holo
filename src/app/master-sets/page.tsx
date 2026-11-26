"use client";

import { Check, Grid3x3, Search, X } from "lucide-react";
import Link from "next/link";
import { useDeferredValue, useEffect, useMemo, useRef, useState } from "react";
import { SetArt, useExploreIndex } from "@/components/explore/explore-items";
import { masterSetHref, ProgressBar } from "@/components/master-sets/master-set-items";
import { EmptyPage } from "@/components/portfolio/empty-state";
import { ErrorState } from "@/components/portfolio/error-state";
import { PortfolioBanner, PortfolioSwitcher } from "@/components/portfolio/portfolio-controls";
import { ProductImage } from "@/components/product/product-image";
import { Skeleton } from "@/components/ui/skeleton";
import { ownedSets, useChecklists } from "@/lib/checklists";
import { parseEditionSlug } from "@/lib/editions";
import type { ExploreSet } from "@/lib/explore/types";
import type { HoldingView } from "@/lib/finance/portfolio";
import { orderGames, shortGameName } from "@/lib/games";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";

/** A set on the page: the catalog entry (art, release date) when found, and your progress. */
interface Row {
  id: string;
  name: string;
  art: ExploreSet | null;
  holdings: HoldingView[];
  owned: number;
  total: number | null;
  ratio: number | null;
}

const BRAND_KEY = "master-sets-brand";

function savedBrand(): string {
  try {
    return localStorage.getItem(BRAND_KEY) || "pokemon";
  } catch {
    return "pokemon";
  }
}

/**
 * Master Sets, like the app: the games as big titles, then the sets you've started (most complete
 * first) and every other set of that game (newest first), each as a grid of tiles.
 */
export default function MasterSetsPage() {
  const store = useStore();
  const { holdings } = usePortfolio();
  const owned = useMemo(() => ownedSets(holdings), [holdings]);
  const index = useExploreIndex();
  const catalog = useMemo(() => (index.status === "ready" ? index.sets : []), [index]);
  const indexTried = index.status !== "loading";
  const [brand, setBrandState] = useState("pokemon");
  const [searching, setSearching] = useState(false);
  const [query, setQuery] = useState("");
  const settledQuery = useDeferredValue(query);

  useEffect(() => setBrandState(savedBrand()), []);
  const setBrand = (b: string) => {
    setBrandState(b);
    try {
      localStorage.setItem(BRAND_KEY, b);
    } catch {
      /* the pick just isn't remembered */
    }
  };

  // Catalog lookups, rebuilt only when the set list changes.
  const lookups = useMemo(() => {
    const bySlug = new Map(catalog.map((s) => [s.slug, s]));
    const byName = new Map(catalog.map((s) => [s.name.toLowerCase(), s]));
    // An old set split by edition ("base-set--unlimited") takes its catalog set's art and game.
    const find = (id: string, name: string) => bySlug.get(id) ?? byName.get(name.toLowerCase()) ?? bySlug.get(parseEditionSlug(id)?.slug ?? "") ?? null;
    return { find };
  }, [catalog]);

  // Every game in the catalog: Pokémon, One Piece, Lorcana, Magic, the rest, Pokémon Japan last.
  const brands = useMemo(() => {
    const games = index.status === "ready" ? index.games : [];
    const list = games.some((g) => g.slug === "pokemon") ? games : [{ slug: "pokemon", name: "Pokémon", sets: 0 }, ...games];
    return orderGames(list.map((g) => ({ slug: g.slug, name: g.name, sets: g.sets })));
  }, [index]);
  const brandName = shortGameName(brands.find((b) => b.slug === brand)?.name ?? "Pokémon");

  // Your sets in the chosen game. A set the catalog doesn't know (a demo set) counts as Pokémon.
  const mineInBrand = useMemo(() => owned.filter((s) => (lookups.find(s.setId, s.name)?.gameSlug ?? "pokemon") === brand), [owned, lookups, brand]);
  const checklists = useChecklists(mineInBrand);

  const { started, rest } = useMemo(() => {
    let started: Row[] = mineInBrand.map((s) => {
      const list = checklists[s.setId]?.checklist ?? null;
      const ids = new Set(s.holdings.map((h) => h.identity.productId));
      const have = list ? list.cards.filter((c) => ids.has(c.productId)).length : ids.size;
      const total = list?.cards.length ?? null;
      return { id: s.setId, name: s.name, art: lookups.find(s.setId, s.name), holdings: s.holdings, owned: have, total, ratio: total ? have / total : total === 0 ? 0 : null };
    });
    const ids = new Set(started.map((r) => r.id));
    const names = new Set(started.map((r) => r.name.toLowerCase()));
    let rest: Row[] = catalog
      .filter((s) => s.loaded && s.gameSlug === brand && !ids.has(s.slug) && !names.has(s.name.toLowerCase()))
      .map((s) => ({ id: s.slug, name: s.name, art: s, holdings: [], owned: 0, total: null, ratio: null }));
    const q = settledQuery.trim().toLowerCase();
    if (q) {
      started = started.filter((r) => r.name.toLowerCase().includes(q));
      rest = rest.filter((r) => r.name.toLowerCase().includes(q));
    }
    started.sort((a, b) => (b.ratio ?? -1) - (a.ratio ?? -1) || b.owned - a.owned);
    rest.sort((a, b) => (b.art?.releaseDate ?? "").localeCompare(a.art?.releaseDate ?? ""));
    return { started, rest };
  }, [mineInBrand, checklists, lookups, catalog, brand, settledQuery]);

  if (store.status === "loading") return <MasterSetsSkeleton />;
  if (store.status === "error") return <ErrorState message={store.error} />;

  return (
    <div className="animate-fade-in">
      <PortfolioSwitcher compact className="mb-3 lg:hidden" />
      {/* The page's name, small like the app's bar title; the big titles are the games. */}
      <div className="flex h-10 items-center justify-between gap-3">
        <h1 className="text-[17px] font-semibold">Master Sets</h1>
        <button
          type="button"
          onClick={() => {
            setSearching((v) => !v);
            setQuery("");
          }}
          aria-label={searching ? "Close search" : "Search sets"}
          className="-mr-2 flex size-10 items-center justify-center rounded-full text-foreground transition-colors hover:bg-foreground/[0.08]"
        >
          {searching ? <X className="size-5" /> : <Search className="size-5" />}
        </button>
      </div>
      <PortfolioBanner />

      {/* The search field takes the game titles' place in the same 48px slot, so nothing below moves. */}
      <div className="relative mt-1 h-12">
        {searching ? (
          <div key="search" className="relative h-full animate-fade-in">
            <Search className="pointer-events-none absolute left-4 top-1/2 size-4 -translate-y-1/2 text-muted" />
            <input
              autoFocus
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Escape") {
                  setSearching(false);
                  setQuery("");
                }
              }}
              placeholder={`Search ${brandName} sets`}
              aria-label={`Search ${brandName} sets`}
              className="h-full w-full rounded-full bg-foreground/[0.06] pl-10 pr-4 text-[16px] outline-none ring-1 ring-inset ring-foreground/10 backdrop-blur-xl placeholder:text-muted focus:bg-foreground/[0.09]"
            />
          </div>
        ) : (
          <GameTitles key="titles" brands={brands} brand={brand} onPick={setBrand} />
        )}
      </div>

      <div className="mt-4 space-y-8">
        {started.length > 0 && <Group title="Sets started" rows={started} />}
        {rest.length > 0 && <Group title="All sets" rows={rest} />}
        {!started.length && !rest.length && (settledQuery.trim() ? (
          <p className="py-10 text-center text-[15px] text-muted">Nothing matches.</p>
        ) : indexTried ? (
          <EmptyPage title={`No ${brandName} sets yet`} line="Add a few cards and your sets appear here." symbol={Grid3x3} action="Search cards" href="/search" />
        ) : (
          <TileGridSkeleton />
        ))}
      </div>
    </div>
  );
}

/** The games as big display titles: the one shown white, the rest faded, scrolling sideways. */
function GameTitles({ brands, brand, onPick }: { brands: { slug: string; name: string }[]; brand: string; onPick: (slug: string) => void }) {
  const row = useRef<HTMLDivElement>(null);
  const first = useRef(true);
  // The game you're on is always in view (the list of games arrives after the page).
  useEffect(() => {
    const el = row.current?.querySelector<HTMLElement>(`[data-slug="${CSS.escape(brand)}"]`);
    const box = row.current;
    if (!el || !box) return;
    const left = first.current ? el.offsetLeft - box.offsetLeft : el.offsetLeft - box.offsetLeft - (box.clientWidth - el.offsetWidth) / 2;
    box.scrollTo({ left: Math.max(0, left), behavior: first.current ? "auto" : "smooth" });
    first.current = false;
  }, [brand, brands.length]);
  return (
    <div ref={row} className="fade-row scrollbar-none relative h-full overflow-x-auto" role="tablist" aria-label="Games">
      <div className="flex h-full w-max items-center gap-5 pr-11">
        {brands.map((b) => {
          const on = b.slug === brand;
          return (
            <button
              key={b.slug}
              type="button"
              role="tab"
              aria-selected={on}
              data-slug={b.slug}
              onClick={() => !on && onPick(b.slug)}
              className={cn("whitespace-nowrap font-display text-[32px] leading-none tracking-[-0.03em] transition-colors", on ? "text-foreground" : "text-subtle hover:text-muted")}
            >
              {shortGameName(b.name)}
            </button>
          );
        })}
      </div>
    </div>
  );
}

/** A group's heading with how many sets are in it (quiet beside it), and its sets as tiles. */
function Group({ title, rows }: { title: string; rows: Row[] }) {
  return (
    <section>
      <h2 className="mb-3.5 flex items-baseline gap-2 font-display text-[18px] leading-none sm:text-[19px]">
        {title}
        <span className="tabular font-sans text-[15px] font-normal tracking-normal text-muted">{rows.length}</span>
      </h2>
      <div className="grid grid-cols-2 gap-x-3.5 gap-y-5 md:grid-cols-3 xl:grid-cols-4">
        {rows.map((r) => (
          <MasterSetTile key={r.id} row={r} />
        ))}
      </div>
    </section>
  );
}

/** "1st Edition" / "Unlimited" at the end of an old set's name, for its tag. */
function editionTag(name: string): string | null {
  if (name.endsWith(" 1st Edition")) return "1ST ED.";
  if (name.endsWith(" Unlimited")) return "UNLIMITED";
  return null;
}

/** The name without its edition ("Team Rocket Unlimited" → "Team Rocket"). */
function shortSetName(name: string): string {
  for (const cut of [" 1st Edition", " Unlimited"]) if (name.endsWith(cut)) return name.slice(0, -cut.length);
  return name;
}

function monthYear(iso: string | null | undefined): string | null {
  if (!iso) return null;
  const d = new Date(`${iso}T00:00:00`);
  return Number.isNaN(d.getTime()) ? null : d.toLocaleDateString("en-US", { month: "short", year: "numeric" });
}

/**
 * A set as a grid tile (the app's MasterSetTile): its banner art in a rounded 3:2 frame, then its
 * name and "8 of 102" with a thin lime bar. A finished set gets a lime Complete tag on its art.
 */
function MasterSetTile({ row: r }: { row: Row }) {
  const started = r.holdings.length > 0;
  const complete = started && r.total !== null && r.total > 0 && r.owned >= r.total;
  const edition = editionTag(r.name);
  const subtitle =
    r.total !== null
      ? started
        ? `${r.owned} of ${r.total}`
        : `${r.total} cards`
      : !started
        ? (monthYear(r.art?.releaseDate) ?? "Not started")
        : `${r.owned} card${r.owned === 1 ? "" : "s"}`;
  const cover = r.art ? null : [...r.holdings].sort((a, b) => (b.value ?? 0) - (a.value ?? 0))[0];
  return (
    <Link href={masterSetHref(r.id)} className="group block min-w-0 [contain-intrinsic-size:auto_220px] [content-visibility:auto]">
      <div className={cn("relative aspect-[3/2] overflow-hidden rounded-2xl ring-1 ring-inset", complete ? "ring-lime/60" : "ring-border")}>
        {r.art ? (
          <SetArt set={r.art} className="absolute inset-0" />
        ) : (
          // No catalog entry (a demo set): your best card from it, tilted on a faint glow.
          <div className="absolute inset-0 flex items-center justify-center bg-image-well" style={{ backgroundImage: "radial-gradient(120% 90% at 30% 0%, color-mix(in srgb, var(--lime) 14%, transparent), transparent 70%)" }}>
            {cover && <ProductImage product={cover.product} grade={cover.identity.grade} slabKey={cover.key} size="xs" frame={false} className="h-[56%] w-auto rotate-6 overflow-hidden rounded-[4px]" />}
          </div>
        )}
        {complete && <span className="tag-skew tag-lime absolute left-2.5 top-2.5">
            <Check className="size-2.5" strokeWidth={3} /> Complete
          </span>}
        {edition && (
          <span className="absolute bottom-2 left-2 rounded-full bg-black/55 px-[7px] py-1 font-mono text-[10px] leading-none tracking-[0.08em] text-white backdrop-blur-sm">{edition}</span>
        )}
      </div>
      <div className="mt-2.5">
        <p className="truncate text-[14px] font-medium">{shortSetName(r.name)}</p>
        <p className="tabular mt-0.5 truncate text-[12px] text-muted">{subtitle}</p>
        {started && r.ratio !== null && <ProgressBar value={r.ratio} className="mt-1.5 h-[3px] bg-foreground/10" />}
      </div>
    </Link>
  );
}

function TileGridSkeleton() {
  return (
    <div className="grid grid-cols-2 gap-x-3.5 gap-y-5 md:grid-cols-3 xl:grid-cols-4">
      {Array.from({ length: 6 }).map((_, i) => (
        <div key={i}>
          <Skeleton className="aspect-[3/2] rounded-2xl" />
          <Skeleton className="mt-2.5 h-3.5 w-3/4" />
          <Skeleton className="mt-1.5 h-3 w-1/3" />
        </div>
      ))}
    </div>
  );
}

function MasterSetsSkeleton() {
  return (
    <div aria-busy="true">
      <Skeleton className="h-5 w-28" />
      <Skeleton className="mt-4 h-9 w-64" />
      <div className="mt-6">
        <TileGridSkeleton />
      </div>
    </div>
  );
}
