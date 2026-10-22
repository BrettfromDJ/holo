"use client";

import { useId, useMemo } from "react";
import { Area, AreaChart, Line, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { formatShortDate, moneyCompact } from "@/lib/format";
import { cn } from "@/lib/utils";

export interface ScrubPoint {
  date: string;
  value: number | null;
  /** Optional secondary line (e.g. invested capital), drawn dashed and muted. */
  secondary?: number | null;
}

/**
 * Fey-style line chart: a thin neutral line with a faint wash beneath it, a
 * dotted baseline at the starting value, a hairline crosshair on hover, and
 * no grid. Direction shows only in the hover dot; the numbers carry color. Hover position is reported to the parent so the headline number
 * can "scrub" with the cursor.
 */
export function ScrubChart({
  data,
  tone,
  baseline,
  onScrub,
  height = 260,
  showAxis = true,
  className,
  secondaryLabel,
}: {
  data: ScrubPoint[];
  tone: "up" | "down" | "flat";
  baseline?: number | null;
  onScrub?: (index: number | null) => void;
  height?: number;
  showAxis?: boolean;
  className?: string;
  secondaryLabel?: string;
}) {
  const gid = useId().replace(/[^a-zA-Z0-9]/g, "");
  const color = "var(--chart-line)";
  const dot = tone === "down" ? "var(--down)" : tone === "up" ? "var(--up)" : "var(--muted)";
  const hasSecondary = data.some((d) => d.secondary !== undefined && d.secondary !== null);

  const domain = useMemo(() => {
    const vals: number[] = [];
    for (const d of data) {
      if (d.value !== null) vals.push(d.value);
      if (d.secondary !== undefined && d.secondary !== null) vals.push(d.secondary);
    }
    if (baseline !== null && baseline !== undefined) vals.push(baseline);
    if (!vals.length) return [0, 1] as [number, number];
    const min = Math.min(...vals);
    const max = Math.max(...vals);
    const pad = (max - min || Math.abs(max) * 0.05 || 1) * 0.08;
    return [min - pad, max + pad] as [number, number];
  }, [data, baseline]);

  return (
    <div className={cn("w-full select-none", className)} style={{ height }} onMouseLeave={() => onScrub?.(null)}>
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart
          data={data}
          margin={{ top: 8, right: showAxis ? 4 : 0, bottom: 0, left: 0 }}
          onMouseMove={(s) => {
            const i = s?.activeTooltipIndex;
            onScrub?.(i === undefined || i === null ? null : Number(i));
          }}
          onMouseLeave={() => onScrub?.(null)}
        >
          <defs>
            <linearGradient id={`fill-${gid}`} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={color} stopOpacity={0.07} />
              <stop offset="100%" stopColor={color} stopOpacity={0} />
            </linearGradient>
          </defs>
          <XAxis dataKey="date" hide />
          <YAxis
            domain={domain}
            orientation="right"
            hide={!showAxis}
            width={showAxis ? 56 : 0}
            axisLine={false}
            tickLine={false}
            tickCount={4}
            tick={{ fill: "var(--subtle)", fontSize: 11 }}
            tickFormatter={(v: number) => moneyCompact(v)}
          />
          {baseline !== null && baseline !== undefined && (
            <ReferenceLine y={baseline} stroke="var(--subtle)" strokeDasharray="1 4" strokeWidth={1.25} ifOverflow="extendDomain" />
          )}
          <Tooltip
            cursor={{ stroke: "var(--border-strong)", strokeWidth: 1 }}
            isAnimationActive={false}
            content={({ active, payload }) =>
              active && payload?.length ? (
                <div className="tabular rounded-[5px] border border-border bg-surface-2 px-1.5 py-0.5 text-[11px] text-muted">{formatShortDate(String(payload[0].payload.date))}</div>
              ) : null
            }
            position={{ y: 0 }}
          />
          {hasSecondary && (
            <Line
              type="monotone"
              dataKey="secondary"
              name={secondaryLabel}
              stroke="var(--violet)"
              strokeWidth={1.25}
              strokeDasharray="3 3"
              dot={false}
              activeDot={false}
              isAnimationActive={false}
              connectNulls={false}
            />
          )}
          <Area
            type="monotone"
            dataKey="value"
            stroke={color}
            strokeWidth={1.25}
            fill={`url(#fill-${gid})`}
            dot={false}
            activeDot={{ r: 3.5, fill: dot, stroke: "var(--stage)", strokeWidth: 2 }}
            isAnimationActive={false}
            connectNulls={false}
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
