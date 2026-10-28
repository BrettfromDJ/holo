"use client";

import { InsideTick } from "./inside-tick";
import { useId, useMemo } from "react";
import { Area, AreaChart, Line, ReferenceDot, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { formatShortDate, moneyCompact } from "@/lib/format";
import { cn } from "@/lib/utils";

export interface ScrubPoint {
  date: string;
  value: number | null;
  /** Optional secondary line (e.g. invested capital), drawn dashed and muted. */
  secondary?: number | null;
}

/** An event pinned to the line, e.g. a purchase or sale. */
export interface ChartMarker {
  date: string;
  kind: "buy" | "sell";
  /** One-line description shown in the hover label, e.g. "Bought 2 × $135.00". */
  label: string;
}

/**
 * Apple Stocks–style line chart: a single 2px line colored by direction, a
 * dotted baseline at the starting value, a hairline crosshair on hover, and
 * no grid. Hover position is reported to the parent so the headline number
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
  markers,
}: {
  data: ScrubPoint[];
  tone: "up" | "down" | "flat";
  baseline?: number | null;
  onScrub?: (index: number | null) => void;
  height?: number;
  showAxis?: boolean;
  className?: string;
  secondaryLabel?: string;
  markers?: ChartMarker[];
}) {
  const gid = useId().replace(/[^a-zA-Z0-9]/g, "");
  const color = tone === "down" ? "var(--down)" : tone === "up" ? "var(--up)" : "var(--muted)";
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

  // Pin each marker to the first charted day on or after its date, so an
  // event on a day without a price still lands on the line.
  const pins = useMemo(() => {
    const byDate = new Map<string, { date: string; value: number; events: ChartMarker[] }>();
    if (!markers?.length || !data.length) return byDate;
    for (const m of markers) {
      if (m.date < data[0].date) continue;
      const point = data.find((d) => d.date >= m.date && d.value !== null);
      if (!point || point.value === null) continue;
      const pin = byDate.get(point.date) ?? { date: point.date, value: point.value, events: [] };
      pin.events.push(m);
      byDate.set(point.date, pin);
    }
    return byDate;
  }, [markers, data]);

  return (
    <div className={cn("w-full select-none", className)} style={{ height }} onMouseLeave={() => onScrub?.(null)}>
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart
          data={data}
          margin={{ top: 16, right: 0, bottom: 0, left: 0 }}
          onMouseMove={(s) => {
            const i = s?.activeTooltipIndex;
            onScrub?.(i === undefined || i === null ? null : Number(i));
          }}
          onMouseLeave={() => onScrub?.(null)}
        >
          <defs>
            <linearGradient id={`fill-${gid}`} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={color} stopOpacity={0.14} />
              <stop offset="100%" stopColor={color} stopOpacity={0} />
            </linearGradient>
          </defs>
          <XAxis dataKey="date" hide />
          <YAxis
            domain={domain}
            orientation="right"
            hide={!showAxis}
            // Labels sit inside the plot along the right edge (just above each
            // gridline) so the line can run the full width, no empty gutter.
            width={1}
            axisLine={false}
            tickLine={false}
            tickCount={4}
            tick={(props: object) => <InsideTick {...props} format={moneyCompact} />}
          />
          {baseline !== null && baseline !== undefined && (
            <ReferenceLine y={baseline} stroke="var(--subtle)" strokeDasharray="1 4" strokeWidth={1.25} ifOverflow="extendDomain" />
          )}
          <Tooltip
            cursor={{ stroke: "var(--border-strong)", strokeWidth: 1 }}
            isAnimationActive={false}
            content={({ active, payload }) => {
              if (!active || !payload?.length) return null;
              const date = String(payload[0].payload.date);
              const pin = pins.get(date);
              return (
                <div className="tabular rounded-md bg-surface-3/90 px-2 py-1 text-[11px] text-muted">
                  {formatShortDate(date)}
                  {pin?.events.map((e, i) => (
                    <span key={i} className={cn("ml-1.5 font-medium", e.kind === "buy" ? "text-foreground" : "text-down")}>
                      · {e.label}
                    </span>
                  ))}
                </div>
              );
            }}
            position={{ y: 0 }}
          />
          {hasSecondary && (
            <Line
              type="monotone"
              dataKey="secondary"
              name={secondaryLabel}
              stroke="var(--subtle)"
              strokeWidth={1.5}
              strokeDasharray="4 4"
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
            strokeWidth={2}
            fill={`url(#fill-${gid})`}
            dot={false}
            activeDot={{ r: 4.5, fill: color, stroke: "var(--background)", strokeWidth: 2 }}
            isAnimationActive={false}
            connectNulls={false}
          />
          {[...pins.values()].map((pin) => {
            const sell = pin.events.every((e) => e.kind === "sell");
            return [
              <ReferenceLine key={`l-${pin.date}`} x={pin.date} stroke="var(--border-strong)" strokeDasharray="2 3" ifOverflow="hidden" />,
              <ReferenceDot
                key={`d-${pin.date}`}
                x={pin.date}
                y={pin.value}
                ifOverflow="visible"
                shape={(props: { cx?: number; cy?: number }) => (
                  <g className="animate-pop" style={{ transformBox: "fill-box", transformOrigin: "center" }}>
                    <circle cx={props.cx} cy={props.cy} r={9} fill={sell ? "var(--down)" : "var(--foreground)"} opacity={0.18} />
                    <circle cx={props.cx} cy={props.cy} r={5} fill={sell ? "var(--down)" : "var(--foreground)"} stroke="var(--background)" strokeWidth={2} />
                    {pin.events.length > 1 && (
                      <text x={(props.cx ?? 0) + 9} y={(props.cy ?? 0) - 8} fontSize={10} fontWeight={600} fill="var(--foreground)">
                        ×{pin.events.length}
                      </text>
                    )}
                  </g>
                )}
              />,
            ];
          })}
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
