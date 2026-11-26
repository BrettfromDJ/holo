"use client";

import { ChevronRight, MoreHorizontal, Search } from "lucide-react";
import Link from "next/link";
import { cn } from "@/lib/utils";

/**
 * Chips like the app's `ChipPicker`: separate 13px glass tiles, the picked one white with dark
 * text, no track behind them. `scrolls` lets a long row scroll inside the margins.
 */
export function Chips<T extends string | number>({
  options,
  value,
  onChange,
  label,
  scrolls,
  fill,
  className,
}: {
  options: { value: T; label: string }[];
  value: T;
  onChange: (v: T) => void;
  label: string;
  scrolls?: boolean;
  /** Each chip takes an equal share of the row (the range chips under a chart). */
  fill?: boolean;
  className?: string;
}) {
  return (
    <div role="group" aria-label={label} className={cn("flex gap-2", scrolls && "scrollbar-none overflow-x-auto", className)}>
      {options.map((o) => (
        <button
          key={String(o.value)}
          type="button"
          aria-pressed={o.value === value}
          onClick={() => onChange(o.value)}
          className={cn("glass-chip h-9 shrink-0 rounded-[13px] px-3.5 text-[14px] font-medium transition-colors", fill && "flex-1")}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

/** The app's GlassStat: a small frosted tile with a quiet label and one figure. */
export function GlassStat({ label, value, tone, href }: { label: string; value: React.ReactNode; tone?: "up" | "down" | "quiet"; href?: string }) {
  const body = (
    <>
      <span className="flex items-center gap-1 font-mono text-[10px] uppercase tracking-[0.1em] text-muted">
        <span className="truncate">{label}</span>
        {href && <ChevronRight className="size-3 shrink-0" />}
      </span>
      <span className={cn("tabular mt-1 block truncate text-[16px] font-semibold", tone === "up" && "text-up", tone === "down" && "text-down", tone === "quiet" && "text-subtle")}>{value}</span>
    </>
  );
  const cls = "glass-stat block min-w-0 flex-1 rounded-[14px] px-3 py-2.5";
  return href ? (
    <Link href={href} className={cn(cls, "transition-opacity hover:opacity-85")}>
      {body}
    </Link>
  ) : (
    <div className={cls}>{body}</div>
  );
}

export const toneOf = (v: number | null | undefined): "up" | "down" | undefined => (v === null || v === undefined || Math.abs(v) < 0.005 ? undefined : v > 0 ? "up" : "down");

/** A section's heading: display type, sentence case, an optional quiet count line. */
export function Heading({ title, subtitle, action }: { title: string; subtitle?: string | null; action?: React.ReactNode }) {
  return (
    <div className="flex items-end justify-between gap-4">
      <div className="min-w-0">
        <h2 className="font-display text-[22px] leading-tight">{title}</h2>
        {subtitle && <p className="tabular mt-0.5 text-[13px] text-muted">{subtitle}</p>}
      </div>
      {action}
    </div>
  );
}

/** The ⋯ at the end of a row of cards (the app's `RowMoreButton`). */
export function RowMore({ href, onClick, label }: { href?: string; onClick?: () => void; label: string }) {
  const cls = "flex size-9 shrink-0 items-center justify-center rounded-full text-muted transition-colors hover:bg-foreground/5 hover:text-foreground";
  return href ? (
    <Link href={href} aria-label={label} className={cls}>
      <MoreHorizontal className="size-[18px]" />
    </Link>
  ) : (
    <button type="button" onClick={onClick} aria-label={label} className={cls}>
      <MoreHorizontal className="size-[18px]" />
    </button>
  );
}

/** A "Find a sale" style search box: one glass capsule. */
export function SearchBox({ value, onChange, placeholder }: { value: string; onChange: (v: string) => void; placeholder: string }) {
  return (
    <label className="glass flex h-12 items-center gap-2 rounded-full px-4">
      <Search className="size-4 shrink-0 text-muted" aria-hidden />
      <input
        type="search"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="min-w-0 flex-1 bg-transparent text-[15px] text-foreground outline-none placeholder:text-subtle"
      />
    </label>
  );
}
