"use client";

import { ArrowUpDown, ChevronDown, Eye, X } from "lucide-react";
import { useState } from "react";
import { DropdownMenu, DropdownMenuContent, DropdownMenuRadioGroup, DropdownMenuRadioItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { activeFilterCount, brandOf, facet, languageOf, NO_FILTERS, type SearchFilters } from "@/lib/explore/filters";
import type { ExploreProduct } from "@/lib/explore/types";
import { moneyWhole } from "@/lib/format";
import { cn } from "@/lib/utils";

const chip = "inline-flex h-9 shrink-0 items-center gap-1.5 rounded-full px-3.5 text-[13px] font-medium transition-colors";
const chipOff = "bg-surface-2 text-muted hover:text-foreground";
const chipOn = "bg-foreground text-background";

const SORTS: { value: SearchFilters["sort"]; label: string }[] = [
  { value: "match", label: "Best match" },
  { value: "price-desc", label: "Price: high to low" },
  { value: "price-asc", label: "Price: low to high" },
  { value: "name", label: "Name" },
];

/** One row of filter chips over search results; scrolls sideways on a phone. Options come from the results themselves. */
export function SearchFilterBar({ items, filters, onChange }: { items: ExploreProduct[]; filters: SearchFilters; onChange: (f: SearchFilters) => void }) {
  const [priceOpen, setPriceOpen] = useState(filters.min !== null || filters.max !== null);
  const set = (patch: Partial<SearchFilters>) => onChange({ ...filters, ...patch });
  const languages = facet(items, (i) => languageOf(i.gameName));
  const brands = facet(items, (i) => brandOf(i.gameName));
  const active = activeFilterCount(filters);
  const priceLabel = filters.min !== null || filters.max !== null ? `${filters.min !== null ? moneyWhole(filters.min) : "$0"}–${filters.max !== null ? moneyWhole(filters.max) : "any"}` : "Price";

  return (
    <div>
      <div className="-mx-4 flex gap-2 overflow-x-auto px-4 pb-1 [scrollbar-width:none] sm:mx-0 sm:flex-wrap sm:px-0">
        <Menu
          label={filters.type === "single" ? "Cards" : filters.type === "sealed" ? "Sealed" : "Type"}
          on={filters.type !== "all"}
          value={filters.type}
          onValue={(v) => set({ type: v as SearchFilters["type"] })}
          options={[
            { value: "all", label: "Cards and sealed" },
            { value: "single", label: "Cards only" },
            { value: "sealed", label: "Sealed only" },
          ]}
        />
        <Menu
          label={filters.language ?? "Language"}
          on={filters.language !== null}
          value={filters.language ?? ""}
          onValue={(v) => set({ language: v || null })}
          options={[{ value: "", label: "Any language" }, ...withSelected(languages, filters.language).map((l) => ({ value: l.value, label: l.value, count: l.count }))]}
        />
        {(brands.length > 1 || filters.brand) && (
          <Menu
            label={filters.brand ?? "Brand"}
            on={filters.brand !== null}
            value={filters.brand ?? ""}
            onValue={(v) => set({ brand: v || null })}
            options={[{ value: "", label: "Every brand" }, ...withSelected(brands, filters.brand).map((b) => ({ value: b.value, label: b.value, count: b.count }))]}
          />
        )}
        <Menu
          label={filters.owned === "owned" ? "Owned" : filters.owned === "not-owned" ? "Not owned" : "Owned"}
          on={filters.owned !== "any"}
          value={filters.owned}
          onValue={(v) => set({ owned: v as SearchFilters["owned"] })}
          options={[
            { value: "any", label: "Owned or not" },
            { value: "owned", label: "In my collection" },
            { value: "not-owned", label: "Not in my collection" },
          ]}
        />
        <button type="button" aria-pressed={filters.watchlist} onClick={() => set({ watchlist: !filters.watchlist })} className={cn(chip, filters.watchlist ? chipOn : chipOff)}>
          <Eye className="size-3.5" /> Watchlist
        </button>
        <button type="button" aria-expanded={priceOpen} onClick={() => setPriceOpen((v) => !v)} className={cn(chip, filters.min !== null || filters.max !== null ? chipOn : chipOff)}>
          <span className="tabular">{priceLabel}</span> <ChevronDown className={cn("size-3.5 transition-transform", priceOpen && "rotate-180")} />
        </button>
        <Menu
          label={SORTS.find((s) => s.value === filters.sort)!.label}
          icon={<ArrowUpDown className="size-3.5" />}
          on={false}
          value={filters.sort}
          onValue={(v) => set({ sort: v as SearchFilters["sort"] })}
          options={SORTS}
          className="sm:ml-auto"
        />
        {active > 0 && (
          <button type="button" onClick={() => onChange({ ...NO_FILTERS, sort: filters.sort })} className={cn(chip, "text-muted hover:text-foreground")}>
            <X className="size-3.5" /> Clear
          </button>
        )}
      </div>
      {priceOpen && (
        <div className="mt-2 flex items-center gap-2 text-[13px] text-muted">
          <PriceInput label="Minimum price" placeholder="Min" value={filters.min} onChange={(min) => set({ min })} />
          <span>to</span>
          <PriceInput label="Maximum price" placeholder="Max" value={filters.max} onChange={(max) => set({ max })} />
        </div>
      )}
    </div>
  );
}

/** Keep the selected value listed even when the current results don't include it. */
function withSelected(list: { value: string; count: number }[], selected: string | null) {
  return selected && !list.some((l) => l.value === selected) ? [...list, { value: selected, count: 0 }] : list;
}

function Menu({
  label,
  icon,
  on,
  value,
  onValue,
  options,
  className,
}: {
  label: string;
  icon?: React.ReactNode;
  on: boolean;
  value: string;
  onValue: (v: string) => void;
  options: { value: string; label: string; count?: number }[];
  className?: string;
}) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger className={cn(chip, on ? chipOn : chipOff, className)}>
        {icon}
        {label} <ChevronDown className="size-3.5" />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start">
        <DropdownMenuRadioGroup value={value} onValueChange={onValue}>
          {options.map((o) => (
            <DropdownMenuRadioItem key={o.value} value={o.value} className="justify-between gap-6">
              {o.label}
              {o.count !== undefined && <span className="tabular text-[12px] text-subtle">{o.count}</span>}
            </DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

function PriceInput({ label, placeholder, value, onChange }: { label: string; placeholder: string; value: number | null; onChange: (v: number | null) => void }) {
  return (
    <span className="relative">
      <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-subtle">$</span>
      <input
        inputMode="decimal"
        aria-label={label}
        placeholder={placeholder}
        defaultValue={value ?? ""}
        onChange={(e) => {
          const n = Number(e.target.value.replace(/[^0-9.]/g, ""));
          onChange(e.target.value.trim() === "" || !Number.isFinite(n) ? null : n);
        }}
        className="tabular h-9 w-28 rounded-full bg-surface-2 pl-6 pr-3 text-[16px] text-foreground outline-none placeholder:text-subtle focus:bg-surface-3 sm:text-[13px]"
      />
    </span>
  );
}
