"use client";

import { ArrowUpDown, LayoutGrid, List, Plus, Search, SlidersHorizontal, X } from "lucide-react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useMemo, useState } from "react";
import { EmptyCollection } from "@/components/portfolio/empty-state";
import { ErrorState } from "@/components/portfolio/error-state";
import { HoldingListHeader, HoldingListRow, HoldingTile } from "@/components/portfolio/holding-items";
import { DeltaPill } from "@/components/product/delta";
import { ProductImage } from "@/components/product/product-image";
import { PageHeader } from "@/components/shell/page-header";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { DropdownMenu, DropdownMenuContent, DropdownMenuLabel, DropdownMenuRadioGroup, DropdownMenuRadioItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Segmented } from "@/components/ui/segmented";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { categoryOf, PRODUCT_CATEGORIES } from "@/lib/catalog";
import type { HoldingView } from "@/lib/finance/portfolio";
import { money } from "@/lib/format";
import { usePortfolio, useStore } from "@/lib/store/collection-store";
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
  const view = store.data.preferences.defaultView;

  const sets = useMemo(() => [...new Set(holdings.map((h) => h.product?.setName).filter((s): s is string => Boolean(s)))].sort(), [holdings]);
  const categories = useMemo(() => PRODUCT_CATEGORIES.filter((c) => holdings.some((h) => h.product && categoryOf(h.product) === c)), [holdings]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    const list = holdings.filter((h) => {
      if (kind !== "all" && kind !== "watchlist" && h.category !== kind) return false;
      if (setName !== "all" && h.product?.setName !== setName) return false;
      if (category !== "all" && (!h.product || categoryOf(h.product) !== category)) return false;
      if (perf === "profit" && !(h.unrealized !== null && h.unrealized > 0)) return false;
      if (perf === "loss" && !(h.unrealized !== null && h.unrealized < 0)) return false;
      if (q && !`${h.product?.name} ${h.product?.setName} ${h.product?.productType}`.toLowerCase().includes(q)) return false;
      return true;
    });
    return sortHoldings(list, sort);
  }, [holdings, kind, setName, category, perf, query, sort]);

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
        subtitle={
          kind === "watchlist" ? (
            "Products you're watching — not part of your portfolio"
          ) : (
            <span className="tabular">
              {filtered.length} holding{filtered.length === 1 ? "" : "s"} · {money(totals.value)} · <DeltaPill ratio={totals.pct} />
            </span>
          )
        }
        actions={
          <Button variant="brand" onClick={() => store.openAdd()} className="hidden sm:inline-flex">
            <Plus /> Add
          </Button>
        }
      />

      {/* Toolbar */}
      <div className="sticky top-16 z-20 -mx-5 bg-background/90 px-5 py-3 backdrop-blur-xl sm:-mx-8 sm:px-8">
        <div className="flex flex-wrap items-center gap-2">
          <div className="relative min-w-[200px] flex-1">
            <Search className="pointer-events-none absolute left-4 top-1/2 size-[18px] -translate-y-1/2 text-subtle" />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search your collection"
              aria-label="Search your collection"
              className="h-11 w-full rounded-full bg-surface pl-11 pr-10 text-[15px] shadow-card outline-none placeholder:text-subtle focus:ring-4 focus:ring-brand/15"
            />
            {query && (
              <button onClick={() => setQuery("")} aria-label="Clear search" className="absolute right-3 top-1/2 -translate-y-1/2 text-subtle hover:text-foreground">
                <X className="size-4" />
              </button>
            )}
          </div>
          <Button variant={showFilters || activeFilters ? "outline" : "secondary"} onClick={() => setShowFilters((s) => !s)} aria-expanded={showFilters}>
            <SlidersHorizontal /> Filters{activeFilters ? ` · ${activeFilters}` : ""}
          </Button>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="secondary" aria-label="Sort">
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

        <div className="scrollbar-none -mx-1 mt-3 flex gap-1.5 overflow-x-auto px-1">
          {KINDS.map((k) => (
            <button
              key={k.value}
              onClick={() => {
                setKind(k.value);
                router.replace(k.value === "all" ? "/collection" : `/collection?kind=${k.value}`, { scroll: false });
              }}
              aria-pressed={kind === k.value}
              className={cn(
                "h-10 shrink-0 rounded-full px-4 text-[14px] font-semibold transition-colors",
                kind === k.value ? "bg-accent text-accent-foreground" : "bg-surface text-muted shadow-card hover:text-foreground",
              )}
            >
              {k.label}
            </button>
          ))}
        </div>

        {showFilters && (
          <div className="mt-3 grid gap-2 animate-rise sm:grid-cols-3">
            <FilterSelect label="Set" value={setName} onChange={setSetName} options={sets} allLabel="All sets" />
            <FilterSelect label="Product type" value={category} onChange={setCategory} options={categories} allLabel="All product types" />
            <Select value={perf} onValueChange={(v) => setPerf(v as Perf)}>
              <SelectTrigger aria-label="Performance" className="h-11">
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

      <div className="mt-4">
        {kind === "watchlist" ? (
          <WatchGrid query={query} />
        ) : !filtered.length ? (
          <div className="py-20 text-center">
            <p className="font-medium">No holdings match</p>
            <p className="mt-1 text-sm text-muted">Try clearing a filter or searching for something else.</p>
          </div>
        ) : view === "grid" ? (
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 sm:gap-5 xl:grid-cols-4">
            {filtered.map((h) => (
              <HoldingTile key={h.key} h={h} />
            ))}
          </div>
        ) : (
          <Card className="overflow-hidden pt-4">
            <HoldingListHeader />
            <div className="divide-y divide-border">
              {filtered.map((h) => (
                <HoldingListRow key={h.key} h={h} />
              ))}
            </div>
          </Card>
        )}
      </div>
    </div>
  );
}

function FilterSelect({ label, value, onChange, options, allLabel }: { label: string; value: string; onChange: (v: string) => void; options: readonly string[]; allLabel: string }) {
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger aria-label={label} className="h-11">
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
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 sm:gap-5 xl:grid-cols-4">
      {items.map((w) => {
        const p = data.products[w.productId];
        const price = data.prices[priceKey(w.productId, w.printing)];
        return (
          <Link key={w.id} href={`/product/${encodeURIComponent(w.productId)}`} className="group">
            <div className="relative">
              <ProductImage product={p} className="aspect-square w-full rounded-[1.35rem]" />
              <span className="absolute left-2.5 top-2.5 rounded-full bg-surface/90 px-2.5 py-1 text-[12px] font-semibold text-muted shadow-card backdrop-blur">Watching</span>
            </div>
            <p className="mt-3 truncate px-2 text-[15px] font-semibold">{p?.name}</p>
            <p className="truncate text-[12px] text-muted">{p?.setName}</p>
            <div className="mt-2 flex items-center justify-between">
              <span className="tabular text-[18px] font-bold">{money(price?.market ?? null)}</span>
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
      <Skeleton className="mt-8 h-11 w-full rounded-full" />
      <div className="mt-6 grid grid-cols-2 gap-4 sm:grid-cols-3 xl:grid-cols-4">
        {Array.from({ length: 8 }).map((_, i) => (
          <div key={i}>
            <Skeleton className="aspect-square w-full rounded-[var(--radius-card)]" />
            <Skeleton className="mt-3 h-4 w-3/4" />
            <Skeleton className="mt-2 h-4 w-1/2" />
          </div>
        ))}
      </div>
    </div>
  );
}
