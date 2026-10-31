"use client";

import { Grid3x3, Plus } from "lucide-react";
import Link from "next/link";
import { useMemo, useState } from "react";
import { SetArt, useExploreIndex } from "@/components/explore/explore-items";
import { LimeChip, masterSetHref, ProgressBar, ProgressRing, SearchSort } from "@/components/master-sets/master-set-items";
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
import { formatDate, money } from "@/lib/format";
import { usePortfolio, useStore } from "@/lib/store/collection-store";

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

          <div className="mt-6 grid grid-cols-2 gap-x-3.5 gap-y-6 md:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5">
            {rows.slice(0, limit).map((r) => (
              <SetTile key={r.id} row={r} />
            ))}
            {scope === "all" && index.status === "loading" && Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="aspect-[3/2] rounded-2xl" />)}
          </div>
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

/** A set: its banner art with your progress on it, then the name, how many of how many, and a thin bar. */
function SetTile({ row: r }: { row: Row }) {
  const cover = r.art ? null : [...r.holdings].sort((a, b) => (b.value ?? 0) - (a.value ?? 0))[0];
  const started = r.holdings.length > 0;
  const detail =
    r.total !== null
      ? `${r.owned} of ${r.total} cards`
      : !started
        ? r.art?.releaseDate
          ? formatDate(r.art.releaseDate)
          : " "
        : `${r.owned} card${r.owned === 1 ? "" : "s"}`;
  return (
    <Link href={masterSetHref(r.id)} className="group flex min-w-0 flex-col">
      <div className="relative aspect-[3/2] overflow-hidden rounded-2xl border border-border transition-colors group-hover:border-border-strong">
        {r.art ? (
          <SetArt set={r.art} className="h-full w-full" />
        ) : (
          <div className="flex h-full w-full items-center justify-center bg-image-well p-2.5">
            {cover && <ProductImage product={cover.product} grade={cover.identity.grade} slabKey={cover.key} size="sm" frame={false} className="aspect-[63/88] h-full max-w-full" />}
          </div>
        )}
        {started && r.ratio !== null ? (
          <span className="tabular absolute bottom-2 left-2 flex items-center gap-1.5 rounded-full bg-black/60 py-[5px] pl-2 pr-2.5 text-[12px] font-bold text-white backdrop-blur-sm">
            <ProgressRing value={r.ratio} />
            {Math.round(r.ratio * 100)}%
          </span>
        ) : !started ? (
          <span className="absolute bottom-2 left-2 rounded-full bg-black/60 px-2 py-1 text-[11px] font-semibold text-white/60 backdrop-blur-sm">Not started</span>
        ) : null}
      </div>
      <p className="mt-2.5 truncate text-[14px] font-medium">{r.name}</p>
      <p className="tabular mt-0.5 truncate text-[12px] text-muted">{detail}</p>
      {started && r.ratio !== null && <ProgressBar value={r.ratio} className="mt-2" />}
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
      <div className="mt-10 grid grid-cols-2 gap-3.5 md:grid-cols-3 xl:grid-cols-4">
        {Array.from({ length: 6 }).map((_, i) => (
          <Skeleton key={i} className="aspect-[3/2] rounded-2xl" />
        ))}
      </div>
    </div>
  );
}
