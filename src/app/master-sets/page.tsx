"use client";

import { Grid3x3, Plus } from "lucide-react";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { SetArt, useExploreIndex } from "@/components/explore/explore-items";
import { deckGlow, DotMatrix, gridPattern, LimeChip, masterSetHref, ProgressBar, SearchSort } from "@/components/master-sets/master-set-items";
import { AnimatedNumber } from "@/components/motion/animated-number";
import { ErrorState } from "@/components/portfolio/error-state";
import { PortfolioBanner, PortfolioSwitcher } from "@/components/portfolio/portfolio-controls";
import { ProductImage } from "@/components/product/product-image";
import { PageHeader } from "@/components/shell/page-header";
import { Button } from "@/components/ui/button";
import { Segmented } from "@/components/ui/segmented";
import { Skeleton } from "@/components/ui/skeleton";
import { ownedSets, useChecklists, type OwnedSet } from "@/lib/checklists";
import type { ExploreSet } from "@/lib/explore/types";
import type { HoldingView } from "@/lib/finance/portfolio";
import { money } from "@/lib/format";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { cn } from "@/lib/utils";

type Scope = "mine" | "all";
type Sort = "progress" | "value" | "newest" | "name";

const SORTS: { value: Sort; label: string }[] = [
  { value: "progress", label: "Most complete" },
  { value: "value", label: "Most valuable" },
  { value: "newest", label: "Newest" },
  { value: "name", label: "Name" },
];

/** "All sets" can be thousands long: shown a page at a time. */
const PAGE = 60;

/** A set on the page: the catalog entry (art, release date) when found, and your progress. */
interface Row {
  id: string;
  name: string;
  art: ExploreSet | null;
  holdings: HoldingView[];
  owned: number;
  total: number | null;
  value: number;
  ratio: number | null;
}

export default function MasterSetsPage() {
  const store = useStore();
  const { holdings } = usePortfolio();
  const owned = useMemo(() => ownedSets(holdings), [holdings]);
  const checklists = useChecklists(owned);
  const index = useExploreIndex();
  const [scope, setScope] = useState<Scope>("mine");
  const [sort, setSort] = useState<Sort>("progress");
  const [query, setQuery] = useState("");
  const [limit, setLimit] = useState(PAGE);

  const catalog = index.status === "ready" ? index.sets : null;

  const mine: Row[] = useMemo(() => {
    const bySlug = new Map((catalog ?? []).map((s) => [s.slug, s]));
    const byName = new Map((catalog ?? []).map((s) => [s.name.toLowerCase(), s]));
    return owned.map((s: OwnedSet) => {
      const list = checklists[s.setId]?.checklist ?? null;
      const ids = new Set(s.holdings.map((h) => h.identity.productId));
      const have = list ? list.cards.filter((c) => ids.has(c.productId)).length : ids.size;
      const total = list?.cards.length ?? null;
      return {
        id: s.setId,
        name: s.name,
        art: bySlug.get(s.setId) ?? byName.get(s.name.toLowerCase()) ?? null,
        holdings: s.holdings,
        owned: have,
        total,
        value: s.holdings.reduce((sum, h) => sum + (h.value ?? 0), 0),
        ratio: total ? have / total : total === 0 ? 0 : null,
      };
    });
  }, [owned, checklists, catalog]);

  const rows: Row[] = useMemo(() => {
    let list = mine;
    if (scope === "all" && catalog) {
      const ids = new Set(mine.map((r) => r.id));
      const names = new Set(mine.map((r) => r.name.toLowerCase()));
      list = [
        ...list,
        ...catalog
          .filter((s) => s.loaded && !ids.has(s.slug) && !names.has(s.name.toLowerCase()))
          .map((s) => ({ id: s.slug, name: s.name, art: s, holdings: [], owned: 0, total: null, value: 0, ratio: null })),
      ];
    }
    const q = query.trim().toLowerCase();
    if (q) list = list.filter((r) => r.name.toLowerCase().includes(q));
    const sorted = [...list];
    switch (sort) {
      case "progress":
        return sorted.sort((a, b) => (b.ratio ?? -1) - (a.ratio ?? -1) || b.owned - a.owned);
      case "value":
        return sorted.sort((a, b) => b.value - a.value);
      case "newest":
        return sorted.sort((a, b) => (b.art?.releaseDate ?? "").localeCompare(a.art?.releaseDate ?? ""));
      case "name":
        return sorted.sort((a, b) => a.name.localeCompare(b.name));
    }
  }, [mine, scope, catalog, query, sort]);

  if (store.status === "loading") return <MasterSetsSkeleton />;
  if (store.status === "error") return <ErrorState message={store.error} />;

  const complete = mine.filter((r) => (r.ratio ?? 0) >= 1).length;
  const best = mine.filter((r) => r.ratio !== null).sort((a, b) => (b.ratio ?? 0) - (a.ratio ?? 0))[0];
  const cards = owned.reduce((sum, s) => sum + new Set(s.holdings.map((h) => h.identity.productId)).size, 0);
  const worth = mine.reduce((sum, r) => sum + r.value, 0);

  return (
    <div className="animate-fade-in">
      <PageHeader
        title="Master sets"
        figure={<AnimatedNumber value={owned.length} format={(n) => String(Math.round(n))} duration={1100} from={owned.length * 0.85} />}
        unit={owned.length === 1 ? "Set started" : "Sets started"}
        note={
          best?.ratio != null ? (
            <span className="flex min-w-0 items-center gap-2">
              <LimeChip>{Math.round(best.ratio * 100)}%</LimeChip>
              <span className="truncate">of {best.name}, your closest</span>
            </span>
          ) : undefined
        }
        stats={[
          { label: "Cards", value: cards },
          { label: "Complete", value: complete },
          { label: "Worth", value: money(worth) },
        ]}
      />
      <PortfolioSwitcher compact className="mb-3 lg:hidden" />
      <PortfolioBanner />

      {!owned.length && scope === "mine" ? (
        <div className="flex flex-col items-center py-20 text-center">
          <Grid3x3 className="size-10 text-subtle" strokeWidth={1.5} />
          <p className="mt-4 font-medium">No singles yet</p>
          <p className="mt-1 max-w-sm text-sm text-muted">Add a single card and its set appears here, with every card in it and how close you are to the full set.</p>
          <div className="mt-6 flex gap-2">
            <Button variant="primary" onClick={() => store.openAdd()}>
              <Plus /> Add a card
            </Button>
            <Button variant="secondary" onClick={() => setScope("all")}>
              Browse all sets
            </Button>
          </div>
        </div>
      ) : (
        <>
          <div className="space-y-3">
            <SearchSort query={query} onQuery={setQuery} placeholder="Search sets" sort={sort} onSort={setSort} sorts={SORTS} />
            <Segmented
              ariaLabel="Which sets"
              value={scope}
              onChange={(v) => {
                setScope(v);
                setLimit(PAGE);
              }}
              options={[
                { value: "mine", label: "Your sets" },
                { value: "all", label: "All sets" },
              ]}
            />
          </div>

          {scope === "all" && index.status === "error" && <p className="mt-4 rounded-xl bg-surface px-4 py-3 text-[13px] text-muted">Couldn&apos;t load the catalog ({index.message}). Showing your sets.</p>}

          <SetDeck rows={rows.slice(0, limit)} loading={scope === "all" && index.status === "loading"} />
          {!rows.length && !(scope === "all" && index.status === "loading") && <p className="py-10 text-center text-[15px] text-muted">Nothing matches.</p>}
          {rows.length > limit && (
            <div className="mt-8 flex justify-center">
              <Button variant="secondary" onClick={() => setLimit((l) => l + PAGE)}>
                Show more sets
              </Button>
            </div>
          )}
        </>
      )}
    </div>
  );
}

/** Deck columns for the page width: one on phones, two on tablets, three on wide screens. */
function useDeckColumns() {
  const [cols, setCols] = useState(1);
  useEffect(() => {
    const md = matchMedia("(min-width: 768px)");
    const xl = matchMedia("(min-width: 1280px)");
    const update = () => setCols(xl.matches ? 3 : md.matches ? 2 : 1);
    update();
    md.addEventListener("change", update);
    xl.addEventListener("change", update);
    return () => {
      md.removeEventListener("change", update);
      xl.removeEventListener("change", update);
    };
  }, []);
  return cols;
}

/** How far each deck card slides under the one after it (the app's SetDeckCard.overlap). */
const OVERLAP = 70;

/**
 * The sets as a deck of tall cards, each overlapping the one above so you see its name and
 * progress; the last one shows in full. On wider screens the list is dealt into side-by-side
 * decks, read top to bottom, column by column.
 */
function SetDeck({ rows, loading }: { rows: Row[]; loading: boolean }) {
  // At least four cards to a deck, so the overlap still reads as a deck.
  const cols = Math.max(1, Math.min(useDeckColumns(), Math.ceil(rows.length / 4)));
  const per = Math.ceil(rows.length / cols);
  const decks = Array.from({ length: cols }, (_, c) => rows.slice(c * per, (c + 1) * per)).filter((d) => d.length);
  return (
    <div className={cn("mt-6 grid items-start gap-x-4 gap-y-4", cols === 1 && "max-w-[560px]")} style={{ gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))` }}>
      {decks.map((deck, c) => (
        <div key={c} className="flex flex-col">
          {deck.map((r, i) => (
            <SetDeckCard key={r.id} row={r} style={i ? { marginTop: -OVERLAP } : undefined} />
          ))}
        </div>
      ))}
      {loading && !rows.length && <Skeleton className="h-[196px] rounded-[28px]" />}
    </div>
  );
}

/**
 * One set in the deck: a tall dark card with a lime, blue or pink glow of its own and a faint
 * grid. The top shows the name, how many of how many and the % in lime dot-matrix digits (what
 * you see while it's overlapped); the bottom has a thin lime bar and the set's art, tilted.
 */
function SetDeckCard({ row: r, style }: { row: Row; style?: React.CSSProperties }) {
  const cover = r.art?.iconUrl || r.art?.imageUrl ? null : [...r.holdings].sort((a, b) => (b.value ?? 0) - (a.value ?? 0))[0];
  const started = r.holdings.length > 0;
  const pct = started && r.ratio !== null ? Math.round(r.ratio * 100) : null;
  const detail = r.total !== null ? `${r.owned} of ${r.total} cards` : !started ? "Not started" : `${r.owned} card${r.owned === 1 ? "" : "s"}`;
  return (
    <Link
      href={masterSetHref(r.id)}
      style={style}
      className="group relative isolate block h-[196px] overflow-hidden rounded-[28px] border border-border bg-surface shadow-[0_-4px_20px_rgb(0_0_0/0.55)] transition-transform duration-300 ease-[var(--ease-apple)] hover:-translate-y-1.5 focus-visible:-translate-y-1.5"
    >
      <div aria-hidden className="absolute inset-0 -z-10" style={{ backgroundImage: deckGlow(r.id) }} />
      <div aria-hidden className="absolute inset-0 -z-10" style={gridPattern(26, "color-mix(in srgb, var(--foreground) 7%, transparent)")} />
      {(r.art?.iconUrl || r.art?.imageUrl || cover) && (
        <div aria-hidden className="absolute -bottom-2.5 -right-4 -z-10 h-[100px] w-[150px] rotate-[-6deg] overflow-hidden rounded-[10px] opacity-60">
          {r.art?.iconUrl || r.art?.imageUrl ? (
            <SetArt set={r.art} className="h-full w-full" />
          ) : (
            cover && <ProductImage product={cover.product} grade={cover.identity.grade} slabKey={cover.key} size="sm" frame={false} className="h-full w-full" />
          )}
        </div>
      )}
      <div className="flex h-full flex-col p-5">
        <div className="flex items-start gap-2.5">
          <div className="min-w-0 flex-1">
            <p className="truncate text-[22px] font-semibold leading-tight tracking-[-0.02em]">{r.name}</p>
            <p className="tabular mt-1 truncate text-[13px] text-muted">{detail}</p>
          </div>
          {pct !== null && (
            <span className="flex shrink-0 items-start gap-0.5 pt-1">
              <DotMatrix text={String(pct)} dot={3.4} />
              <span className="-mt-0.5 text-[12px] text-lime">%</span>
            </span>
          )}
        </div>
        {pct !== null && <ProgressBar value={r.ratio ?? 0} className="mt-auto w-full max-w-[200px]" />}
      </div>
    </Link>
  );
}

function MasterSetsSkeleton() {
  return (
    <div aria-busy="true">
      <Skeleton className="h-4 w-28" />
      <Skeleton className="mt-3 h-14 w-64" />
      <div className="mt-5 grid max-w-[560px] grid-cols-3 gap-2">
        {Array.from({ length: 3 }).map((_, i) => (
          <Skeleton key={i} className="h-[58px] rounded-[14px]" />
        ))}
      </div>
      <div className="mt-10 flex max-w-[560px] flex-col">
        {Array.from({ length: 4 }).map((_, i) => (
          <Skeleton key={i} className="h-[196px] rounded-[28px] border border-background" style={i ? { marginTop: -OVERLAP } : undefined} />
        ))}
      </div>
    </div>
  );
}
