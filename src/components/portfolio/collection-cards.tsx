"use client";

import { FlipGrid, FlipItem } from "@/components/motion/flip-grid";
import { Layers, LayoutGrid, List, MoreHorizontal, Pencil, Plus, Search, SlidersHorizontal, Trash2, X } from "lucide-react";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback, useMemo, useState } from "react";
import { BulkBar, SelectableHolding } from "@/components/portfolio/bulk-editor";
import { CATEGORY_OF, CHIP_OF, collectionHref, type CollectionCategory, type CollectionSort } from "@/components/portfolio/collection-links";
import { EmptyPage } from "@/components/portfolio/empty-state";
import { ErrorState } from "@/components/portfolio/error-state";
import { HoldingActionsSheet } from "@/components/portfolio/holding-actions-sheet";
import { HoldingListHeader } from "@/components/portfolio/holding-items";
import { HoldingSheet } from "@/components/portfolio/holding-sheet";
import { ShelfDialog } from "@/components/shelves/shelf-controls";
import { Card } from "@/components/ui/card";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { categoryOf, PRODUCT_CATEGORIES } from "@/lib/catalog";
import type { HoldingCategory, HoldingView } from "@/lib/finance/portfolio";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { ALL, usePortfolios } from "@/lib/store/portfolios";
import { useShelves } from "@/lib/store/shelves";
import { cn } from "@/lib/utils";

type Perf = "all" | "profit" | "loss";

const SORTS: { value: CollectionSort; label: string }[] = [
  { value: "value", label: "Holding value" },
  { value: "gain", label: "Gain" },
  { value: "gainPct", label: "Gain %" },
  { value: "move", label: "Today's move" },
  { value: "date", label: "Recently added" },
  { value: "name", label: "Name" },
];

const CHIPS: { value: CollectionCategory; label: string }[] = [
  { value: "singles", label: "Singles" },
  { value: "sealed", label: "Sealed" },
  { value: "graded", label: "Graded" },
];

function sortHoldings(list: HoldingView[], key: CollectionSort): HoldingView[] {
  const nullLast = (v: number | null) => (v === null ? -Infinity : v);
  const sorted = [...list];
  switch (key) {
    case "value":
      return sorted.sort((a, b) => nullLast(b.value) - nullLast(a.value));
    case "gain":
      return sorted.sort((a, b) => nullLast(b.unrealized) - nullLast(a.unrealized));
    case "gainPct":
      return sorted.sort((a, b) => nullLast(b.unrealizedPct) - nullLast(a.unrealizedPct));
    case "move":
      return sorted.sort((a, b) => nullLast(b.dayChangePct) - nullLast(a.dayChangePct));
    case "date":
      return sorted.sort((a, b) => ((b.lastAcquired ?? "") > (a.lastAcquired ?? "") ? 1 : -1));
    case "name":
      return sorted.sort((a, b) => (a.product?.name ?? "").localeCompare(b.product?.name ?? ""));
  }
}

/** The chip from the link: `cat` (or the old `kind`), if it names one. */
function chipFromParams(params: URLSearchParams): CollectionCategory | null {
  const cat = params.get("cat");
  if (cat === "singles" || cat === "sealed" || cat === "graded") return cat;
  const kind = params.get("kind");
  if (kind === "single" || kind === "sealed" || kind === "graded") return CHIP_OF[kind as HoldingCategory];
  return null;
}

/**
 * Collection's Cards (the app's `CollectionView`): straight to the cards. Nothing above the
 * search but the portfolio's name when one is picked; one glass toolbar (search, a round
 * Sort & filter button with a lime dot when something is set, a round grid/list flip); chips
 * (Singles, Sealed, Graded, then lists, then + List; no All); then the cards. A card opens its
 * page; each row's ⋯ opens its actions (Your copy, Select, Add to list, Delete).
 */
export function CollectionCards() {
  const store = useStore();
  const { holdings } = usePortfolio();
  const params = useSearchParams();
  const router = useRouter();
  const { selected: portfolio, nameOf } = usePortfolios();
  const { shelves, remove: removeShelf } = useShelves();

  const [query, setQuery] = useState("");
  const [chip, setChip] = useState<CollectionCategory | null>(() => chipFromParams(params));
  const [sort, setSort] = useState<CollectionSort>(() => (SORTS.some((s) => s.value === params.get("sort")) ? (params.get("sort") as CollectionSort) : "value"));
  const [setName, setSetName] = useState("all");
  const [category, setCategory] = useState("all");
  const [perf, setPerf] = useState<Perf>("all");
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [shelfId, setShelfId] = useState<string | null>(params.get("list") ?? params.get("shelf"));
  const [shelfDialog, setShelfDialog] = useState<"new" | "edit" | null>(null);
  const [opened, setOpened] = useState<HoldingView | null>(null);
  const [actionsFor, setActionsFor] = useState<HoldingView | null>(null);
  const [selecting, setSelecting] = useState(false);
  const [picked, setPicked] = useState<Set<string>>(() => new Set());
  const toggle = useCallback(
    (key: string) =>
      setPicked((s) => {
        const next = new Set(s);
        if (next.has(key)) next.delete(key);
        else next.add(key);
        return next;
      }),
    [],
  );
  const shelf = shelves.find((x) => x.id === shelfId) ?? null;
  const view = store.data.preferences.defaultView;

  const counts = useMemo(() => {
    const c: Record<HoldingCategory, number> = { single: 0, sealed: 0, graded: 0 };
    for (const h of holdings) c[h.category]++;
    return c;
  }, [holdings]);
  const chips = CHIPS.filter((c) => counts[CATEGORY_OF[c.value]] > 0);
  // Opens on Singles, or Sealed when that's all you have (the app's `activeCategory`).
  const activeCategory: CollectionCategory | null = chip && counts[CATEGORY_OF[chip]] > 0 ? chip : (chips[0]?.value ?? null);

  const sets = useMemo(() => [...new Set(holdings.map((h) => h.product?.setName).filter((s): s is string => Boolean(s)))].sort(), [holdings]);
  const categories = useMemo(() => PRODUCT_CATEGORIES.filter((c) => holdings.some((h) => h.product && categoryOf(h.product) === c)), [holdings]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    const list = holdings.filter((h) => {
      if (shelf) {
        if (!shelf.productIds.includes(h.identity.productId)) return false;
      } else if (activeCategory && h.category !== CATEGORY_OF[activeCategory]) return false;
      if (setName !== "all" && h.product?.setName !== setName) return false;
      if (category !== "all" && (!h.product || categoryOf(h.product) !== category)) return false;
      if (perf === "profit" && !(h.unrealized !== null && h.unrealized > 0)) return false;
      if (perf === "loss" && !(h.unrealized !== null && h.unrealized < 0)) return false;
      if (q && !`${h.product?.name} ${h.product?.setName} ${h.product?.productType}`.toLowerCase().includes(q)) return false;
      return true;
    });
    return sortHoldings(list, sort);
  }, [holdings, activeCategory, setName, category, perf, query, sort, shelf]);

  const pickedShown = useMemo(() => (selecting ? filtered.filter((h) => picked.has(h.key)) : []), [selecting, filtered, picked]);
  const filterCount = (setName !== "all" ? 1 : 0) + (category !== "all" ? 1 : 0) + (perf !== "all" ? 1 : 0) + (sort !== "value" ? 1 : 0);

  const go = (next: { cat?: CollectionCategory; list?: string }) => router.replace(collectionHref({ ...next, sort }), { scroll: false });
  const startSelect = useCallback((h: HoldingView) => {
    setPicked(new Set([h.key]));
    setSelecting(true);
  }, []);

  if (store.status === "loading") return <CardsSkeleton />;
  if (store.status === "error") return <ErrorState message={store.error} />;

  return (
    <div className="animate-fade-in">
      {portfolio !== ALL && <p className="mb-2 truncate text-[15px] font-semibold">{nameOf(portfolio)}</p>}
      {!holdings.length ? (
        <EmptyPage title="Nothing here yet" line="Scan a card, or search for anything you own." action="Search cards" href="/search" link="Browse Explore" linkHref="/explore" />
      ) : (
        <>
          {/* Toolbar: one glass family. */}
          <div className="sticky top-[calc(3.5rem+env(safe-area-inset-top))] z-20 -mx-4 bg-background/85 px-4 py-2.5 backdrop-blur-xl sm:-mx-8 sm:px-8 lg:top-0">
            <div className="flex items-center gap-2">
              <div className="relative min-w-0 flex-1">
                <Search className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-subtle" />
                <input
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  placeholder="Search your cards"
                  aria-label="Search your collection"
                  className="glass h-11 w-full rounded-full bg-transparent pl-10 pr-9 text-[15px] outline-none placeholder:text-subtle"
                />
                {query && (
                  <button onClick={() => setQuery("")} aria-label="Clear search" className="absolute right-3.5 top-1/2 -translate-y-1/2 text-subtle hover:text-foreground">
                    <X className="size-4" />
                  </button>
                )}
              </div>
              <button type="button" onClick={() => setFiltersOpen(true)} aria-label={filterCount ? `Sort & filter (${filterCount} set)` : "Sort & filter"} className="glass relative flex size-11 shrink-0 items-center justify-center rounded-full">
                <SlidersHorizontal className="size-[18px]" />
                {filterCount > 0 && <span aria-hidden className="absolute right-2 top-2 size-2 rounded-full bg-lime shadow-[0_0_6px_var(--lime)]" />}
              </button>
              <button
                type="button"
                onClick={() => void store.savePreferences({ defaultView: view === "grid" ? "list" : "grid" })}
                aria-label={view === "grid" ? "Show as a list" : "Show as a grid"}
                className="glass flex size-11 shrink-0 items-center justify-center rounded-full"
              >
                {view === "grid" ? <List className="size-[18px]" /> : <LayoutGrid className="size-[18px]" />}
              </button>
            </div>

            {/* Chips: separate glass tiles, the picked one white; the row scrolls inside the margins. */}
            <div className="fade-row scrollbar-none -mb-1 mt-2.5 flex gap-2 overflow-x-auto pb-1">
              {chips.map((c) => (
                <button
                  key={c.value}
                  type="button"
                  aria-pressed={!shelf && activeCategory === c.value}
                  onClick={() => {
                    setChip(c.value);
                    setShelfId(null);
                    go({ cat: c.value });
                  }}
                  className="glass-chip h-9 shrink-0 rounded-[13px] px-4 text-[14px] font-medium"
                >
                  {c.label}
                </button>
              ))}
              {shelves.map((x) =>
                shelf?.id === x.id ? (
                  <DropdownMenu key={x.id}>
                    <DropdownMenuTrigger aria-pressed className="glass-chip flex h-9 shrink-0 items-center gap-1.5 rounded-[13px] pl-4 pr-3 text-[14px] font-medium" aria-label={`${x.name}: list options`}>
                      {x.name}
                      <MoreHorizontal className="size-4 opacity-70" />
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="start">
                      <DropdownMenuItem onSelect={() => setShelfDialog("edit")}>
                        <Pencil className="size-4" /> Rename list
                      </DropdownMenuItem>
                      <DropdownMenuItem
                        className="text-down"
                        onSelect={() => {
                          if (!confirm(`Delete the list "${x.name}"? Your cards stay in your collection.`)) return;
                          void removeShelf(x.id).then(() => {
                            setShelfId(null);
                            go({});
                          });
                        }}
                      >
                        <Trash2 className="size-4" /> Delete list
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                ) : (
                  <button
                    key={x.id}
                    type="button"
                    aria-pressed={false}
                    onClick={() => {
                      setShelfId(x.id);
                      go({ list: x.id });
                    }}
                    className="glass-chip h-9 shrink-0 rounded-[13px] px-4 text-[14px] font-medium"
                  >
                    {x.name}
                  </button>
                ),
              )}
              <button type="button" onClick={() => setShelfDialog("new")} className="glass-chip flex h-9 shrink-0 items-center gap-1 rounded-[13px] px-3.5 text-[14px] font-medium text-muted">
                <Plus className="size-4" /> List
              </button>
            </div>
          </div>

          <div className="mt-4">
            {filtered.some((h) => h.conditionEstimate) && <p className="mb-4 text-[12px] text-subtle">≈ Estimated from the Near Mint price for the card&apos;s{" "}condition.</p>}
            {shelf && !shelf.productIds.length ? (
              <EmptyPage symbol={Layers} icon={Search} title="This list is empty" line="Open any card and use Add to list to put it here." action="Explore cards" href="/explore" />
            ) : !filtered.length ? (
              <p className="py-20 text-center text-[15px] text-muted">Nothing matches.</p>
            ) : view === "grid" ? (
              <FlipGrid className="grid grid-cols-2 gap-x-5 gap-y-10 sm:grid-cols-3 lg:grid-cols-4">
                {filtered.map((h, i) => (
                  <FlipItem key={h.key} flipKey={h.key} index={i}>
                    <SelectableHolding h={h} view="grid" selecting={selecting} selected={selecting && picked.has(h.key)} onToggle={toggle} onMore={setActionsFor} />
                  </FlipItem>
                ))}
              </FlipGrid>
            ) : (
              <Card className="overflow-hidden pt-3">
                <HoldingListHeader className="pr-[3.25rem]" />
                <div className="divide-y divide-border">
                  {filtered.map((h, i) => (
                    <div key={h.key} className="animate-rise" style={{ animationDelay: `${Math.min(i, 16) * 30}ms` }}>
                      <SelectableHolding h={h} view="list" selecting={selecting} selected={selecting && picked.has(h.key)} onToggle={toggle} onMore={setActionsFor} />
                    </div>
                  ))}
                </div>
              </Card>
            )}
          </div>
        </>
      )}

      <ShelfDialog
        open={shelfDialog !== null}
        onOpenChange={(o) => !o && setShelfDialog(null)}
        shelf={shelfDialog === "edit" ? shelf : null}
        onSaved={(x) => {
          setShelfId(x.id);
          go({ list: x.id });
        }}
      />
      <SortFilterSheet
        open={filtersOpen}
        onOpenChange={setFiltersOpen}
        sort={sort}
        onSort={setSort}
        sets={sets}
        setName={setName}
        onSetName={setSetName}
        categories={categories}
        category={category}
        onCategory={setCategory}
        perf={perf}
        onPerf={setPerf}
        onReset={() => {
          setSort("value");
          setSetName("all");
          setCategory("all");
          setPerf("all");
        }}
      />
      {selecting && (
        <BulkBar
          selected={pickedShown}
          shownCount={filtered.length}
          onSelectAll={() => setPicked(new Set(filtered.map((h) => h.key)))}
          onSelectNone={() => setPicked(new Set())}
          onDone={() => setSelecting(false)}
        />
      )}
      <HoldingActionsSheet holding={actionsFor} onOpenChange={(o) => !o && setActionsFor(null)} onYourCopy={setOpened} onSelect={startSelect} />
      <HoldingSheet holding={opened} onOpenChange={(o) => !o && setOpened(null)} />
    </div>
  );
}

/** One "Sort & filter" sheet (the app's `FilterSheet`): sort, set, product type, performance; Reset and Done. */
function SortFilterSheet(props: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  sort: CollectionSort;
  onSort: (s: CollectionSort) => void;
  sets: string[];
  setName: string;
  onSetName: (s: string) => void;
  categories: readonly string[];
  category: string;
  onCategory: (s: string) => void;
  perf: Perf;
  onPerf: (p: Perf) => void;
  onReset: () => void;
}) {
  const label = "mb-2 font-mono text-[10px] font-medium uppercase tracking-[0.08em] text-subtle";
  return (
    <Dialog open={props.open} onOpenChange={props.onOpenChange}>
      <DialogContent hideClose className="bg-[#161618] p-5 pb-[calc(1.25rem+env(safe-area-inset-bottom))] sm:max-w-md sm:pb-5">
        <div className="flex items-center justify-between gap-3">
          <button type="button" onClick={props.onReset} className="text-[15px] font-medium text-muted hover:text-foreground">
            Reset
          </button>
          <DialogTitle className="text-[17px] font-semibold">Sort &amp; filter</DialogTitle>
          <button type="button" onClick={() => props.onOpenChange(false)} className="text-[15px] font-semibold text-lime">
            Done
          </button>
        </div>
        <div className="mt-5 space-y-5 overflow-y-auto">
          <section>
            <p className={label}>Sort by</p>
            <div className="flex flex-wrap gap-2">
              {SORTS.map((s) => (
                <button key={s.value} type="button" aria-pressed={props.sort === s.value} onClick={() => props.onSort(s.value)} className="glass-chip h-9 rounded-[13px] px-3.5 text-[14px] font-medium">
                  {s.label}
                </button>
              ))}
            </div>
          </section>
          <section>
            <p className={label}>Performance</p>
            <div className="flex flex-wrap gap-2">
              {(
                [
                  ["all", "Any"],
                  ["profit", "Up"],
                  ["loss", "Down"],
                ] as const
              ).map(([v, l]) => (
                <button key={v} type="button" aria-pressed={props.perf === v} onClick={() => props.onPerf(v)} className="glass-chip h-9 rounded-[13px] px-3.5 text-[14px] font-medium">
                  {l}
                </button>
              ))}
            </div>
          </section>
          <section className="grid gap-3 sm:grid-cols-2">
            <div>
              <p className={label}>Set</p>
              <FilterSelect label="Set" value={props.setName} onChange={props.onSetName} options={props.sets} allLabel="All sets" />
            </div>
            <div>
              <p className={label}>Product type</p>
              <FilterSelect label="Product type" value={props.category} onChange={props.onCategory} options={props.categories} allLabel="All types" />
            </div>
          </section>
        </div>
      </DialogContent>
    </Dialog>
  );
}

function FilterSelect({ label, value, onChange, options, allLabel }: { label: string; value: string; onChange: (v: string) => void; options: readonly string[]; allLabel: string }) {
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger aria-label={label} className={cn("h-11")}>
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value="all">{allLabel}</SelectItem>
        {options.map((o) => (
          <SelectItem key={o} value={o}>
            {o}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

function CardsSkeleton() {
  return (
    <div aria-busy="true">
      <Skeleton className="h-11 w-full rounded-full" />
      <div className="mt-3 flex gap-2">
        <Skeleton className="h-9 w-20 rounded-[13px]" />
        <Skeleton className="h-9 w-20 rounded-[13px]" />
      </div>
      <div className="mt-6 grid grid-cols-2 gap-4 sm:grid-cols-3 xl:grid-cols-4">
        {Array.from({ length: 8 }).map((_, i) => (
          <div key={i}>
            <Skeleton className="aspect-square w-full rounded-2xl" />
            <Skeleton className="mt-3 h-4 w-3/4" />
            <Skeleton className="mt-2 h-4 w-1/2" />
          </div>
        ))}
      </div>
    </div>
  );
}
