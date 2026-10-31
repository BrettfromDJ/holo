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

/** A disc showing a share as a lit lime wedge, with a dotted ring and 0/25/50/75 around it (the app's GlowPie). */
export function GlowPie({ fraction, size = 168, className }: { fraction: number; size?: number; className?: string }) {
  const f = Math.max(0, Math.min(1, fraction));
  const pad = 30;
  const box = size + pad * 2;
  const c = box / 2;
  const r = size / 2;
  const end = -Math.PI / 2 + f * Math.PI * 2;
  const wedge =
    f >= 0.9999
      ? null
      : `M ${c} ${c} L ${c} ${c - r} A ${r} ${r} 0 ${f > 0.5 ? 1 : 0} 1 ${c + r * Math.cos(end)} ${c + r * Math.sin(end)} Z`;
  const label = (text: string, x: number, y: number) => (
    <text x={x} y={y} textAnchor="middle" dominantBaseline="central" className="font-mono" fontSize={10} fill="rgb(255 255 255 / 0.7)">
      {text}
    </text>
  );
  return (
    <svg width={box} height={box} viewBox={`0 0 ${box} ${box}`} className={cn("shrink-0", className)} role="img" aria-label={`${Math.round(f * 100)}% owned`}>
      <defs>
        <linearGradient id="glow-pie-disc" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="white" stopOpacity="0.18" />
          <stop offset="1" stopColor="white" stopOpacity="0.05" />
        </linearGradient>
      </defs>
      <circle cx={c} cy={c} r={r} fill="url(#glow-pie-disc)" />
      {f > 0 && (wedge ? <path d={wedge} fill="var(--lime)" /> : <circle cx={c} cy={c} r={r} fill="var(--lime)" />)}
      <circle cx={c} cy={c} r={r + 8} fill="none" stroke="rgb(255 255 255 / 0.35)" strokeWidth={1} strokeDasharray="1 4" />
      {label("0", c, c - r - 20)}
      {label("25", c + r + 22, c)}
      {label("50", c, c + r + 20)}
      {label("75", c - r - 22, c)}
    </svg>
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
