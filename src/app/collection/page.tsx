"use client";

import { FlipGrid, FlipItem } from "@/components/motion/flip-grid";
import { ArrowUpDown, LayoutGrid, Library, List, MoreHorizontal, Pencil, Plus, Search, SlidersHorizontal, Trash2, X } from "lucide-react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useMemo, useState } from "react";
import { EmptyCollection } from "@/components/portfolio/empty-state";
import { ErrorState } from "@/components/portfolio/error-state";
import { HoldingListHeader, HoldingListRow, HoldingTile } from "@/components/portfolio/holding-items";
import { HoldingSheet } from "@/components/portfolio/holding-sheet";
import { DeltaPill } from "@/components/product/delta";
import { ProductImage } from "@/components/product/product-image";
import { PortfolioBanner, PortfolioSwitcher } from "@/components/portfolio/portfolio-controls";
import { PageHeader } from "@/components/shell/page-header";
import { ShelfDialog } from "@/components/shelves/shelf-controls";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuRadioGroup, DropdownMenuRadioItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Segmented } from "@/components/ui/segmented";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { categoryOf, PRODUCT_CATEGORIES } from "@/lib/catalog";
import type { HoldingView } from "@/lib/finance/portfolio";
import { money, signedMoney, signedPct } from "@/lib/format";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
import { useShelves } from "@/lib/store/shelves";
import { priceKey } from "@/lib/types";
import { cn } from "@/lib/utils";

type Kind = "all" | "sealed" | "single" | "graded" | "watchlist";
type SortKey = "value" | "gain" | "gainPct" | "date" | "name" | "move";
type Perf = "all" | "profit" | "loss";

const SORTS: { value: SortKey; label: string }[] = [
  { value: "value", label: "Holding value" },
  { value: "gain", label: "Gain / loss ($)" },
  { value: "gainPct", label: "Gain / loss (%)" },
  { value: "move", label: "Price movement (1D)" },
  { value: "date", label: "Purchase date" },
  { value: "name", label: "Name" },
];

const KINDS: { value: Kind; label: string }[] = [
  { value: "all", label: "All" },
  { value: "sealed", label: "Sealed" },
  { value: "single", label: "Singles" },
  { value: "graded", label: "Graded" },
  { value: "watchlist", label: "Watchlist" },
];

function sortHoldings(list: HoldingView[], key: SortKey): HoldingView[] {
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

export default function CollectionPage() {
  return (
    <Suspense fallback={<GridSkeleton />}>
      <Collection />
    </Suspense>
  );
}

function Collection() {
  const store = useStore();
  const { holdings } = usePortfolio();
  const params = useSearchParams();
  const router = useRouter();

  const [query, setQuery] = useState("");
  const [kind, setKind] = useState<Kind>((params.get("kind") as Kind) ?? "all");
  const [sort, setSort] = useState<SortKey>((params.get("sort") as SortKey) ?? "value");
  const [setName, setSetName] = useState<string>("all");
  const [category, setCategory] = useState<string>("all");
  const [perf, setPerf] = useState<Perf>("all");
  const [showFilters, setShowFilters] = useState(false);
  const { shelves, remove: removeShelf } = useShelves();
  const [shelfId, setShelfId] = useState<string | null>(params.get("shelf"));
  const [shelfDialog, setShelfDialog] = useState<"new" | "edit" | null>(null);
  // Your copy, opened in a sheet when a holding is clicked.
  const [opened, setOpened] = useState<HoldingView | null>(null);
  const shelf = shelves.find((x) => x.id === shelfId) ?? null;
  const view = store.data.preferences.defaultView;

  const sets = useMemo(() => [...new Set(holdings.map((h) => h.product?.setName).filter((s): s is string => Boolean(s)))].sort(), [holdings]);
  const categories = useMemo(() => PRODUCT_CATEGORIES.filter((c) => holdings.some((h) => h.product && categoryOf(h.product) === c)), [holdings]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    const list = holdings.filter((h) => {
      if (shelf && !shelf.productIds.includes(h.identity.productId)) return false;
      if (kind !== "all" && kind !== "watchlist" && h.category !== kind) return false;
      if (setName !== "all" && h.product?.setName !== setName) return false;
      if (category !== "all" && (!h.product || categoryOf(h.product) !== category)) return false;
      if (perf === "profit" && !(h.unrealized !== null && h.unrealized > 0)) return false;
      if (perf === "loss" && !(h.unrealized !== null && h.unrealized < 0)) return false;
      if (q && !`${h.product?.name} ${h.product?.setName} ${h.product?.productType}`.toLowerCase().includes(q)) return false;
      return true;
    });
    return sortHoldings(list, sort);
  }, [holdings, kind, setName, category, perf, query, sort, shelf]);

  const totals = useMemo(() => {
    let value = 0;
    let cost = 0;
    for (const h of filtered) {
      if (h.value !== null) {
        value += h.value;
        cost += h.costBasis;
      }
    }
    return { value, gain: value - cost, pct: cost > 0 ? (value - cost) / cost : null };
  }, [filtered]);

  const kindCounts: Record<Kind, number> = {
    all: holdings.length,
    sealed: holdings.filter((h) => h.category === "sealed").length,
    single: holdings.filter((h) => h.category === "single").length,
    graded: holdings.filter((h) => h.category === "graded").length,
    watchlist: store.data.watchlist.length,
  };
  const activeFilters = (setName !== "all" ? 1 : 0) + (category !== "all" ? 1 : 0) + (perf !== "all" ? 1 : 0);

  if (store.status === "loading") return <GridSkeleton />;
  if (store.status === "error") return <ErrorState message={store.error} />;
  if (!holdings.length && kind !== "watchlist") {
    return (
      <>
        <PageHeader title="Collection" />
        <EmptyCollection title="Your collection is empty" />
      </>
    );
  }

  return (
    <div className="animate-fade-in">
      <PageHeader
        title="Collection"
        className="mb-5"
        subtitle={kind === "watchlist" ? "Products you're watching — not part of your portfolio" : undefined}
        actions={
          <Button variant="primary" onClick={() => store.openAdd()} className="hidden sm:inline-flex">
            <Plus /> Add
          </Button>
        }
      />
      {kind !== "watchlist" && (
        // What's in view right now: value first, then the gain (only its numbers colored) and the count.
        // Like the product page's price: the same display face as the title, but much larger so it clearly leads.
        <dl className="mb-6 grid grid-cols-2 items-end gap-x-8 gap-y-4 sm:flex">
          <div className="col-span-2">
            <dt className="font-mono text-[10px] font-medium uppercase tracking-[0.06em] text-subtle">Value</dt>
            <dd className="tabular mt-1.5 font-display text-[56px] leading-[0.95] sm:text-[68px]">{money(totals.value)}</dd>
          </div>
          <div>
            <dt className="font-mono text-[10px] font-medium uppercase tracking-[0.06em] text-subtle">Gain</dt>
            <dd className="tabular mt-1 flex items-baseline gap-2 text-[17px] font-semibold leading-none">
              <span className={totals.gain >= 0 ? "text-up" : "text-down"}>{signedMoney(totals.gain)}</span>
              {totals.pct !== null && <span className={cn("text-[13px] font-medium", totals.gain >= 0 ? "text-up" : "text-down")}>{signedPct(totals.pct)}</span>}
            </dd>
          </div>
          <div>
            <dt className="font-mono text-[10px] font-medium uppercase tracking-[0.06em] text-subtle">{shelf ? shelf.name : kind === "all" ? "Holdings" : KINDS.find((k) => k.value === kind)?.label}</dt>
            <dd className="tabular mt-1 text-[17px] font-semibold leading-none">{filtered.length}</dd>
          </div>
        </dl>
      )}

      <PortfolioSwitcher compact className="mb-3 lg:hidden" />
      <PortfolioBanner />
      {/* Toolbar */}
      <div className="sticky top-[calc(3.5rem+env(safe-area-inset-top))] z-20 -mx-4 bg-background/90 px-4 py-3 backdrop-blur-xl sm:-mx-8 sm:px-8 lg:top-0">
        <div className="flex items-center gap-2">
          <div className="relative min-w-0 flex-1">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-subtle" />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search"
              aria-label="Search your collection"
              className="h-10 w-full rounded-full bg-surface-2 pl-9 pr-9 text-[14px] outline-none placeholder:text-subtle focus:bg-surface-3"
            />
            {query && (
              <button onClick={() => setQuery("")} aria-label="Clear search" className="absolute right-3 top-1/2 -translate-y-1/2 text-subtle hover:text-foreground">
                <X className="size-4" />
              </button>
            )}
          </div>
          <Button
            variant={showFilters || activeFilters ? "outline" : "secondary"}
            onClick={() => setShowFilters((s) => !s)}
            aria-expanded={showFilters}
            aria-label="Filters"
            className="relative max-sm:size-10 max-sm:px-0"
          >
            <SlidersHorizontal /> <span className="hidden sm:inline">Filters{activeFilters ? ` · ${activeFilters}` : ""}</span>
            {activeFilters > 0 && <span className="tabular absolute -right-0.5 -top-0.5 flex size-4 items-center justify-center rounded-full bg-foreground text-[10px] font-semibold text-background sm:hidden">{activeFilters}</span>}
          </Button>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="secondary" aria-label="Sort" className="max-sm:size-10 max-sm:px-0">
                <ArrowUpDown /> <span className="hidden sm:inline">{SORTS.find((s) => s.value === sort)?.label}</span>
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuLabel>Sort by</DropdownMenuLabel>
              <DropdownMenuRadioGroup value={sort} onValueChange={(v) => setSort(v as SortKey)}>
                {SORTS.map((s) => (
                  <DropdownMenuRadioItem key={s.value} value={s.value}>
                    {s.label}
                  </DropdownMenuRadioItem>
                ))}
              </DropdownMenuRadioGroup>
            </DropdownMenuContent>
          </DropdownMenu>
          <Segmented
            ariaLabel="View"
            value={view}
            onChange={(v) => void store.savePreferences({ defaultView: v })}
            options={[
              { value: "grid", label: <LayoutGrid />, title: "Grid view" },
              { value: "list", label: <List />, title: "List view" },
            ]}
          />
        </div>

        <div
          className="scrollbar-none -mx-3 mt-1 -mb-2 flex gap-1.5 overflow-x-auto px-3 py-2 pr-8"
          // Fades at the right edge so it's clear the row scrolls. The padding (offset by negative
          // margins) leaves room for the active chip's glow, which the scroll box would otherwise clip.
          style={{ maskImage: "linear-gradient(90deg, black calc(100% - 40px), transparent)", WebkitMaskImage: "linear-gradient(90deg, black calc(100% - 40px), transparent)" }}
        >
          {KINDS.map((k) => (
            <button
              key={k.value}
              onClick={() => {
                setKind(k.value);
                setShelfId(null);
                router.replace(k.value === "all" ? "/collection" : `/collection?kind=${k.value}`, { scroll: false });
              }}
              aria-pressed={kind === k.value && !shelf}
              className={cn(
                "h-8 shrink-0 rounded-full px-3.5 text-[13px] font-medium transition-colors",
                kind === k.value && !shelf ? "bg-lime font-semibold text-[#0b0b0c] shadow-[0_0_16px_-4px_var(--lime)]" : "bg-surface-2 text-muted hover:text-foreground",
              )}
            >
              {k.label}
              {kindCounts[k.value] > 0 && <span className="tabular ml-1.5 opacity-60">{kindCounts[k.value]}</span>}
            </button>
          ))}
          <span aria-hidden className="mx-1 my-1.5 w-px shrink-0 bg-border" />
          {shelves.map((x) => (
            <button
              key={x.id}
              onClick={() => {
                setKind("all");
                setShelfId(x.id);
                router.replace(`/collection?shelf=${x.id}`, { scroll: false });
              }}
              aria-pressed={shelf?.id === x.id}
              className={cn(
                "flex h-8 shrink-0 items-center gap-1.5 rounded-full px-3.5 text-[13px] font-medium transition-colors",
                shelf?.id === x.id ? "bg-lime font-semibold text-[#0b0b0c] shadow-[0_0_16px_-4px_var(--lime)]" : "bg-surface-2 text-muted hover:text-foreground",
              )}
            >
              {x.name}
              <span className="tabular opacity-60">{x.productIds.length}</span>
            </button>
          ))}
          <button
            onClick={() => setShelfDialog("new")}
            className="flex h-8 shrink-0 items-center gap-1 rounded-full border border-dashed border-border-strong px-3 text-[13px] font-medium text-muted hover:text-foreground"
          >
            <Plus className="size-3.5" /> Shelf
          </button>
        </div>

        {showFilters && (
          <div className="mt-3 grid gap-2 animate-rise sm:grid-cols-3">
            <FilterSelect label="Set" value={setName} onChange={setSetName} options={sets} allLabel="All sets" />
            <FilterSelect label="Product type" value={category} onChange={setCategory} options={categories} allLabel="All product types" />
            <Select value={perf} onValueChange={(v) => setPerf(v as Perf)}>
              <SelectTrigger aria-label="Performance" className="h-10">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Any performance</SelectItem>
                <SelectItem value="profit">Profitable</SelectItem>
                <SelectItem value="loss">Unprofitable</SelectItem>
              </SelectContent>
            </Select>
          </div>
        )}
      </div>

      {shelf && (
        <div className="mt-4 flex animate-rise items-center gap-4 rounded-[var(--radius-card)] border border-border bg-surface px-5 py-4">
          <span className="flex size-12 items-center justify-center rounded-2xl bg-surface-2 text-muted">
            <Library className="size-5" />
          </span>
          <div className="min-w-0 flex-1">
            <p className="truncate text-[17px] font-semibold">{shelf.name}</p>
            <p className="tabular text-[13px] text-muted">
              {filtered.length} product{filtered.length === 1 ? "" : "s"} · {money(totals.value)} <DeltaPill ratio={totals.pct} />
            </p>
          </div>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="icon-sm" aria-label="Shelf options">
                <MoreHorizontal />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem onSelect={() => setShelfDialog("edit")}>
                <Pencil className="size-4" /> Rename
              </DropdownMenuItem>
              <DropdownMenuItem
                className="text-down"
                onSelect={() => {
                  if (!confirm(`Delete the shelf "${shelf.name}"? Your products stay in your collection.`)) return;
                  void removeShelf(shelf.id).then(() => {
                    setShelfId(null);
                    router.replace("/collection", { scroll: false });
                  });
                }}
              >
                <Trash2 className="size-4" /> Delete shelf
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      )}
      <ShelfDialog
        open={shelfDialog !== null}
        onOpenChange={(o) => !o && setShelfDialog(null)}
        shelf={shelfDialog === "edit" ? shelf : null}
        onSaved={(x) => {
          setKind("all");
          setShelfId(x.id);
          router.replace(`/collection?shelf=${x.id}`, { scroll: false });
        }}
      />

      <div className="mt-4">
        {shelf && !filtered.length ? (
          <div className="py-20 text-center">
            <Library className="mx-auto size-8 text-subtle" strokeWidth={1.5} />
            <p className="mt-3 font-medium">This shelf is empty</p>
            <p className="mt-1 text-sm text-muted">Open any product and use “Add to shelf” to put it here.</p>
          </div>
        ) : kind === "watchlist" ? (
          <WatchGrid query={query} />
        ) : !filtered.length ? (
          <div className="py-20 text-center">
            <p className="font-medium">No holdings match</p>
            <p className="mt-1 text-sm text-muted">Try clearing a filter or searching for something else.</p>
          </div>
        ) : view === "grid" ? (
          <FlipGrid className="grid grid-cols-2 gap-x-5 gap-y-10 sm:grid-cols-3 lg:grid-cols-4">
            {filtered.map((h, i) => (
              <FlipItem key={h.key} flipKey={h.key} index={i}>
                <HoldingTile h={h} onOpen={setOpened} />
              </FlipItem>
            ))}
          </FlipGrid>
        ) : (
          <Card className="overflow-hidden pt-3">
            <HoldingListHeader />
            <div className="divide-y divide-border">
              {filtered.map((h, i) => (
                <div key={h.key} className="animate-rise" style={{ animationDelay: `${Math.min(i, 16) * 30}ms` }}>
                  <HoldingListRow h={h} onOpen={setOpened} />
                </div>
              ))}
            </div>
          </Card>
        )}
      </div>
      <HoldingSheet holding={opened} onOpenChange={(o) => !o && setOpened(null)} />
    </div>
  );
}

function FilterSelect({ label, value, onChange, options, allLabel }: { label: string; value: string; onChange: (v: string) => void; options: readonly string[]; allLabel: string }) {
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger aria-label={label} className="h-10">
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

function WatchGrid({ query }: { query: string }) {
  const { data } = useStore();
  const items = data.watchlist.filter((w) => {
    const p = data.products[w.productId];
    return !query || `${p?.name} ${p?.setName}`.toLowerCase().includes(query.toLowerCase());
  });
  if (!items.length) return <p className="py-20 text-center text-sm text-muted">Nothing on your watchlist yet.</p>;
  return (
    <div className="grid grid-cols-2 gap-x-5 gap-y-10 sm:grid-cols-3 lg:grid-cols-4">
      {items.map((w) => {
        const p = data.products[w.productId];
        const price = data.prices[priceKey(w.productId, w.printing)];
        return (
          <Link key={w.id} href={`/product/${encodeURIComponent(w.productId)}`} className="group">
            <div className="relative">
              <ProductImage product={p} className="aspect-square w-full" />
              <span className="absolute left-2.5 top-2.5 rounded-full bg-background/80 px-2 py-0.5 text-[11px] font-medium text-muted backdrop-blur">Watching</span>
            </div>
            <p className="mt-3 truncate text-[14px] font-medium">{p?.name}</p>
            <p className="truncate text-[12px] text-muted">{p?.setName}</p>
            <div className="mt-2 flex items-center justify-between">
              <span className="tabular text-[15px] font-semibold">{money(price?.market ?? null)}</span>
              <DeltaPill ratio={price?.change7dPct != null ? price.change7dPct / 100 : null} />
            </div>
          </Link>
        );
      })}
    </div>
  );
}

function GridSkeleton() {
  return (
    <div aria-busy="true">
      <Skeleton className="h-9 w-48" />
      <Skeleton className="mt-8 h-10 w-full rounded-full" />
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
