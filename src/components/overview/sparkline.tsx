import { useId } from "react";
import { cn } from "@/lib/utils";

/**
 * Tiny trend line for tiles. No axes, no interaction — just the shape.
 * `reference` draws a dashed level (such as what you paid) and is kept in range.
 * The whole chart sweeps in left to right. The clip sits on the <svg> box: on the
 * stretched path itself, with a non-scaling stroke, browsers clip it short.
 */
export function Sparkline({ values, tone, reference, className, height = 48 }: { values: number[]; tone: "up" | "down" | "flat"; reference?: number | null; className?: string; height?: number }) {
  const gid = useId().replace(/[^a-zA-Z0-9]/g, "");
  if (values.length < 2) return null;
  const w = 200;
  const all = reference != null ? [...values, reference] : values;
  const min = Math.min(...all);
  const max = Math.max(...all);
  const span = max - min || 1;
  const y = (v: number) => height - 3 - ((v - min) / span) * (height - 6);
  const pts = values.map((v, i) => [(i / (values.length - 1)) * w, y(v)] as const);
  const line = pts.map(([x, py], i) => `${i ? "L" : "M"}${x.toFixed(1)},${py.toFixed(1)}`).join(" ");
  const color = tone === "down" ? "var(--down)" : tone === "up" ? "var(--up)" : "var(--muted)";
  return (
    <svg viewBox={`0 0 ${w} ${height}`} preserveAspectRatio="none" className={cn("animate-sweep", className)} style={{ height }} aria-hidden>
      <defs>
        <linearGradient id={`sp-${gid}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity={0.22} />
          <stop offset="100%" stopColor={color} stopOpacity={0} />
        </linearGradient>
      </defs>
      <path d={`${line} L${w},${height} L0,${height} Z`} fill={`url(#sp-${gid})`} />
      {reference != null && (
        <line x1={0} x2={w} y1={y(reference)} y2={y(reference)} stroke="var(--muted)" strokeOpacity={0.7} strokeWidth={1} strokeDasharray="3 4" vectorEffect="non-scaling-stroke" />
      )}
      <path d={line} fill="none" stroke={color} strokeWidth={2} vectorEffect="non-scaling-stroke" strokeLinejoin="round" strokeLinecap="round" />
    </svg>
  );
}
