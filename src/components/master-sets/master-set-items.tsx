"use client";

import { ArrowRight, ArrowUpDown, Search, X } from "lucide-react";
import { useEffect, useState } from "react";
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

// MARK: The app's glow pieces (Glow.swift), for the deck and the set page's hero.

const DOT_FONT: Record<string, string[]> = {
  "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
  "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
  "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
  "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
  "4": ["10010", "10010", "10010", "11111", "00010", "00010", "00010"],
  "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
  "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
  "7": ["11111", "00001", "00010", "00100", "00100", "00100", "00100"],
  "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
  "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
  "%": ["11000", "11001", "00010", "00100", "01000", "10011", "00011"],
  "+": ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
  "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
  ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
};

/** Digits drawn as a dot matrix, like an LED display (0-9, %, +, -, .), with a soft glow. */
export function DotMatrix({ text, dot = 3.6, color = "var(--lime)", glow = 8, className }: { text: string; dot?: number; color?: string; glow?: number; className?: string }) {
  const chars = [...text].filter((c) => DOT_FONT[c]);
  const pitch = dot * 1.25;
  const width = Math.max(chars.length * pitch * 6 - pitch, 0);
  const height = pitch * 7;
  const r = dot / 2;
  return (
    <svg
      role="img"
      aria-label={text}
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
      className={cn("shrink-0 overflow-visible", className)}
      style={glow ? { filter: `drop-shadow(0 0 ${glow}px color-mix(in srgb, ${color} 55%, transparent))` } : undefined}
    >
      <g fill={color}>
        {chars.flatMap((ch, n) =>
          DOT_FONT[ch].flatMap((row, y) => [...row].map((bit, x) => (bit === "1" ? <circle key={`${n}-${x}-${y}`} cx={(n * 6 + x) * pitch + r} cy={y * pitch + r} r={r} /> : null))),
        )}
      </g>
    </svg>
  );
}

/** The faint square grid the app lays over its lit surfaces (`GridPattern`). */
export function gridPattern(step: number, line = "rgb(255 255 255 / 0.07)"): React.CSSProperties {
  return {
    backgroundImage: `linear-gradient(to right, ${line} 1px, transparent 1px), linear-gradient(to bottom, ${line} 1px, transparent 1px)`,
    backgroundSize: `${step}px ${step}px`,
  };
}

const ACCENTS = ["var(--lime)", "var(--plan-blue)", "var(--plan-pink)"];

/** A set's own glow, the same every time for the same set: a main lime, blue or pink light and a fainter second one. */
export function deckGlow(id: string): string {
  // FNV-1a, like the app's GlowPalette.forProduct.
  let h = 2166136261;
  for (let i = 0; i < id.length; i++) h = Math.imul(h ^ id.charCodeAt(i), 16777619) >>> 0;
  const main = ACCENTS[h % 3];
  const second = ACCENTS[(h + 1 + ((h >>> 3) % 2)) % 3];
  const x = 15 + ((h >>> 5) % 60);
  return [
    `radial-gradient(70% 90% at ${x}% 0%, color-mix(in srgb, ${main} 26%, transparent), transparent 70%)`,
    `radial-gradient(55% 80% at ${100 - x / 2}% 100%, color-mix(in srgb, ${second} 16%, transparent), transparent 70%)`,
    "linear-gradient(to bottom, rgb(255 255 255 / 0.04), transparent 50%)",
  ].join(", ");
}

/**
 * The set page's dial (the app's GlowPie): a thick ring of frosted glass with a
 * faint lime tint and a fine light edge on both sides, a lime arc with round
 * caps from the top, and an ink arrow in the lime cap where it starts. The arc
 * sweeps in once on mount (not with Reduce Motion).
 */
export function GlowPie({ fraction, size = 180, className }: { fraction: number; size?: number; className?: string }) {
  const f = Math.max(0, Math.min(1, fraction));
  const line = size * 0.2;
  const c = size / 2;
  const mid = c - line / 2;
  // Starts empty and sweeps to the share after the first paint; the CSS transition is off with reduced motion.
  const [shown, setShown] = useState(0);
  useEffect(() => {
    const id = requestAnimationFrame(() => setShown(f));
    return () => cancelAnimationFrame(id);
  }, [f]);
  // Even at 0% the round start shows, so the arrow always has a home.
  const visible = Math.max(shown, 0.0001);
  const arc = {
    pathLength: 1,
    strokeDasharray: "1 1",
    strokeDashoffset: 1 - visible,
    className: "transition-[stroke-dashoffset] delay-150 duration-[900ms] ease-[cubic-bezier(0.3,0,0.2,1)] motion-reduce:transition-none",
  };
  return (
    <div className={cn("relative shrink-0", className)} style={{ width: size, height: size }} role="img" aria-label={`${Math.round(f * 100)}% owned`}>
      {/* The track: frosted glass with a faint lime tint, cut to a ring. */}
      <div
        aria-hidden
        className="absolute inset-0 rounded-full"
        style={{
          background: "linear-gradient(180deg, color-mix(in srgb, var(--lime) 12%, rgb(255 255 255 / 0.09)), color-mix(in srgb, var(--lime) 6%, rgb(255 255 255 / 0.03)))",
          backdropFilter: "blur(12px) saturate(1.5)",
          WebkitBackdropFilter: "blur(12px) saturate(1.5)",
          mask: `radial-gradient(circle closest-side, transparent ${c - line - 0.5}px, #000 ${c - line}px)`,
          WebkitMask: `radial-gradient(circle closest-side, transparent ${c - line - 0.5}px, #000 ${c - line}px)`,
        }}
      />
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="absolute inset-0 overflow-visible" aria-hidden>
        {/* A fine light edge on both sides of the ring. */}
        <circle cx={c} cy={c} r={c - 0.5} fill="none" stroke="rgb(255 255 255 / 0.28)" strokeWidth={1} />
        <circle cx={c} cy={c} r={c - line + 0.5} fill="none" stroke="rgb(255 255 255 / 0.28)" strokeWidth={1} />
        <g transform={`rotate(-90 ${c} ${c})`}>
          {/* A soft glow under the arc: a wider faint stroke, no blur filter. */}
          <circle cx={c} cy={c} r={mid} fill="none" stroke="var(--lime)" strokeOpacity={0.14} strokeWidth={line + 8} strokeLinecap="round" {...arc} />
          <circle cx={c} cy={c} r={mid} fill="none" stroke="var(--lime)" strokeWidth={line} strokeLinecap="round" {...arc} />
        </g>
      </svg>
      {/* The arrow at the top, where the arc begins. */}
      <ArrowRight
        aria-hidden
        strokeWidth={2}
        className="absolute left-1/2 -translate-x-1/2 -translate-y-1/2 text-[#0b0b0c]"
        style={{ top: line / 2, width: line * 0.5, height: line * 0.5 }}
      />
    </div>
  );
}

/** A thin ring with a share drawn on it (the app's GlowRing). */
export function ThinRing({ fraction, size = 38 }: { fraction: number; size?: number }) {
  const r = (size - 2) / 2;
  const f = Math.max(0, Math.min(1, fraction));
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="shrink-0 -rotate-90" aria-hidden>
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="rgb(255 255 255 / 0.35)" strokeWidth={1} />
      {f > 0 && <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="white" strokeWidth={1.6} strokeLinecap="round" pathLength={1} strokeDasharray={`${f} 1`} />}
    </svg>
  );
}

/** A row of ticks with a lime marker at the share: ticks before it bright, after it faint (the app's GlowTicks). */
export function TickBar({ fraction, className }: { fraction: number; className?: string }) {
  const n = 34;
  const cut = Math.round(n * Math.max(0, Math.min(1, fraction)));
  return (
    <div className={cn("relative h-4 w-full", className)} aria-hidden>
      {Array.from({ length: n }, (_, i) => (
        <span
          key={i}
          className={cn("absolute bottom-0 w-px -translate-x-1/2 bg-white", i % 5 === 0 ? "top-2" : "top-[13px]")}
          style={{ left: `${((i + 0.5) / n) * 100}%`, opacity: i < cut ? 0.9 : 0.35 }}
        />
      ))}
      <span
        className="absolute top-0 size-0 -translate-x-1/2 border-x-[5px] border-t-[7px] border-x-transparent border-t-lime"
        style={{ left: `${(cut / n) * 100}%` }}
      />
    </div>
  );
}
