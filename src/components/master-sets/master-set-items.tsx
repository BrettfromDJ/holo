"use client";

import { ArrowUpDown, Search, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { DropdownMenu, DropdownMenuContent, DropdownMenuLabel, DropdownMenuRadioGroup, DropdownMenuRadioItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";

/** Where Master Sets and each set's page live. */
export const MASTER_SETS = "/master-sets";
export const masterSetHref = (setId: string) => `${MASTER_SETS}/${encodeURIComponent(setId)}`;

/** A small lime progress ring (the app's set-tile ring). */
export function ProgressRing({ value, size = 16, stroke = 3, className }: { value: number; size?: number; stroke?: number; className?: string }) {
  const r = (size - stroke) / 2;
  const v = Math.max(0, Math.min(1, value));
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className={cn("shrink-0 -rotate-90", className)} aria-hidden>
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="rgb(255 255 255 / 0.2)" strokeWidth={stroke} />
      {v > 0 && <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--lime)" strokeWidth={stroke} strokeLinecap="round" pathLength={1} strokeDasharray={`${v} 1`} />}
    </svg>
  );
}

/** A thin progress bar in lime. */
export function ProgressBar({ value, className }: { value: number; className?: string }) {
  return (
    <div className={cn("h-1 overflow-hidden rounded-full bg-surface-3", className)} aria-hidden>
      <div className="h-full rounded-full bg-lime transition-[width] duration-700 ease-[var(--ease-apple)]" style={{ width: `${Math.max(0, Math.min(1, value)) * 100}%` }} />
    </div>
  );
}

/** The lime figure chip used in header notes ("72%", "12 of 237"). */
export function LimeChip({ children }: { children: React.ReactNode }) {
  return <span className="tabular rounded-md bg-lime px-2 py-[3px] text-[13px] font-semibold text-[#0b0b0c]">{children}</span>;
}

/** Search field and sort menu side by side, like the app's controls row. */
export function SearchSort<T extends string>({
  query,
  onQuery,
  placeholder,
  sort,
  onSort,
  sorts,
}: {
  query: string;
  onQuery: (q: string) => void;
  placeholder: string;
  sort: T;
  onSort: (s: T) => void;
  sorts: { value: T; label: string }[];
}) {
  return (
    <div className="flex items-center gap-2">
      <div className="relative min-w-0 flex-1 sm:max-w-[420px]">
        <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-subtle" />
        <input
          value={query}
          onChange={(e) => onQuery(e.target.value)}
          placeholder={placeholder}
          aria-label={placeholder}
          className="h-10 w-full rounded-full bg-surface-2 pl-9 pr-9 text-[14px] outline-none placeholder:text-subtle focus:bg-surface-3"
        />
        {query && (
          <button onClick={() => onQuery("")} aria-label="Clear search" className="absolute right-3 top-1/2 -translate-y-1/2 text-subtle hover:text-foreground">
            <X className="size-4" />
          </button>
        )}
      </div>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="secondary" aria-label="Sort" className="max-sm:size-10 max-sm:px-0">
            <ArrowUpDown /> <span className="hidden sm:inline">{sorts.find((s) => s.value === sort)?.label}</span>
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuLabel>Sort by</DropdownMenuLabel>
          <DropdownMenuRadioGroup value={sort} onValueChange={(v) => onSort(v as T)}>
            {sorts.map((s) => (
              <DropdownMenuRadioItem key={s.value} value={s.value}>
                {s.label}
              </DropdownMenuRadioItem>
            ))}
          </DropdownMenuRadioGroup>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  );
}
