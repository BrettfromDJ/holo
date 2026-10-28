"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { CartesianGrid, ResponsiveContainer, Scatter, ScatterChart, Tooltip, Treemap, XAxis, YAxis, ZAxis } from "recharts";
import { InsideTick } from "@/components/charts/inside-tick";
import { Card, SectionTitle } from "@/components/ui/card";
import type { Concentration, GroupPerformance, HoldingPoint, MonthReturn } from "@/lib/finance/analytics";
import type { HoldingView } from "@/lib/finance/portfolio";
import { money, moneyCompact, pct, signedMoney, signedPct } from "@/lib/format";
import { cn } from "@/lib/utils";

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** Green for gains, red for losses, stronger the bigger the move (capped at `cap`). */
export function heat(ret: number, cap = 0.15, max = 0.55) {
  // Square root so small moves still show, without big ones all maxing out.
  const t = Math.sqrt(Math.min(1, Math.abs(ret) / cap));
  const strength = Math.round((0.08 + t * (max - 0.08)) * 100);
  return `color-mix(in srgb, var(${ret >= 0 ? "--up" : "--down"}) ${strength}%, var(--surface-2))`;
}

/* ------------------------------- KPI grid -------------------------------- */

export interface Kpi {
  label: string;
  value: React.ReactNode;
  sub?: React.ReactNode;
}

/** A grid of headline numbers, four across on wider screens. */
const KPI_TINTS = ["tint-lime", "tint-blue", "tint-pink", "tint-blue", "tint-lime", "tint-pink", "tint-blue", "tint-lime"];

export function KpiGrid({ items }: { items: Kpi[] }) {
  return (
    <section aria-label="Key stats" className="grid grid-cols-2 gap-3 sm:grid-cols-4">
      {items.map((k, i) => (
        <div key={k.label} className={cn("tint tint-borderless hype-surface rounded-[var(--radius-card)] px-5 py-4", KPI_TINTS[i % KPI_TINTS.length])}>
          <p className="font-display text-[14px] uppercase leading-none tracking-[0.02em] text-foreground/80">{k.label}</p>
          <p className="hype-num tabular mt-3 text-[26px] leading-none sm:text-[30px]">{k.value}</p>
          {k.sub && <p className="tabular mt-1.5 truncate text-[12px] text-muted">{k.sub}</p>}
        </div>
      ))}
    </section>
  );
}

/** A number colored by its sign (only the number). */
export function Signed({ value, format }: { value: number | null; format: (v: number) => string }) {
  if (value === null) return <span className="text-subtle">—</span>;
  return <span className={value >= 0 ? "text-up" : "text-down"}>{format(value)}</span>;
}

/* ------------------------------ Collection map ---------------------------- */

interface MapNode {
  name: string;
  size: number;
  ret: number | null;
  href: string;
  [k: string]: unknown;
}

/** Gains beyond this show at full strength on the map; losses (which stop at −100%) at LOSS_CAP. */
const MAP_CAP = 2;
const LOSS_CAP = 0.5;
const mapHeat = (ret: number) => heat(ret, ret >= 0 ? MAP_CAP : LOSS_CAP, 0.5);

/** Treemap: each holding sized by value, tinted by its return. */
export function CollectionMap({ holdings }: { holdings: HoldingView[] }) {
  const router = useRouter();
  const data: MapNode[] = holdings
    .filter((h) => (h.value ?? 0) > 0)
    .sort((a, b) => (b.value ?? 0) - (a.value ?? 0))
    .slice(0, 40)
    .map((h) => ({ name: h.product?.name ?? "Unknown", size: h.value!, ret: h.unrealizedPct, href: `/product/${encodeURIComponent(h.identity.productId)}` }));
  if (!data.length) return null;
  return (
    <Card className="min-w-0 p-5 sm:p-6">
      <SectionTitle title="Collection map" subtitle="Each tile is a holding, sized by value and tinted by its return. Tap one to open it." />
      <div className="h-[340px] overflow-hidden rounded-xl sm:h-[420px]">
        <ResponsiveContainer>
          <Treemap
            data={data}
            dataKey="size"
            aspectRatio={1.4}
            isAnimationActive={false}
            onClick={(n) => {
              const href = (n as unknown as MapNode | undefined)?.href;
              if (href) router.push(href);
            }}
            content={<MapTile />}
          />
        </ResponsiveContainer>
      </div>
      <div className="mt-3 flex items-center justify-end gap-2 text-[11px] text-subtle">
        <span className="tabular">−{LOSS_CAP * 100}%</span>
        <span className="h-2 w-32 rounded-full" style={{ background: `linear-gradient(90deg, ${mapHeat(-LOSS_CAP)}, ${mapHeat(0)}, ${mapHeat(MAP_CAP)})` }} />
        <span className="tabular">+{MAP_CAP * 100}%</span>
      </div>
    </Card>
  );
}

function MapTile(props: { x?: number; y?: number; width?: number; height?: number; name?: string; size?: number; ret?: number | null; depth?: number }) {
  const { x = 0, y = 0, width = 0, height = 0, name, size, ret, depth } = props;
  if (depth === 0 || width < 2 || height < 2) return null;
  const showName = width > 70 && height > 38;
  const showValue = width > 70 && height > 56;
  return (
    <g className="cursor-pointer">
      <rect x={x + 1} y={y + 1} width={width - 2} height={height - 2} rx={6} fill={ret === null || ret === undefined ? "var(--surface-2)" : mapHeat(ret)} className="transition-opacity hover:opacity-80" />
      {showName && (
        <foreignObject x={x + 8} y={y + 6} width={width - 16} height={height - 12} className="pointer-events-none">
          <div className="flex h-full flex-col text-foreground">
            <p className="line-clamp-2 text-[12px] font-medium leading-tight">{name}</p>
            {showValue && (
              <p className="tabular mt-auto text-[12px]">
                <span className="font-semibold">{moneyCompact(size ?? 0)}</span>
                {ret !== null && ret !== undefined && <span className="ml-1.5 opacity-80">{signedPct(ret)}</span>}
              </p>
            )}
          </div>
        </foreignObject>
      )}
    </g>
  );
}

/* --------------------------- Monthly returns heatmap ---------------------- */

/** Calendar of monthly returns: one row per year, a cell per month, and the year's total. */
export function ReturnsHeatmap({ months }: { months: MonthReturn[] }) {
  const years = [...new Set(months.map((m) => m.year))].sort((a, b) => b - a);
  if (!months.length) return null;
  const best = months.reduce((a, b) => (b.ret > a.ret ? b : a));
  const worst = months.reduce((a, b) => (b.ret < a.ret ? b : a));
  const positive = months.filter((m) => m.ret > 0).length;
  return (
    <Card className="min-w-0 p-5 sm:p-6">
      <SectionTitle
        title="Monthly returns"
        subtitle={`${positive} of ${months.length} months up · best ${MONTHS[best.month]} ${best.year} (${signedPct(best.ret)}), worst ${MONTHS[worst.month]} ${worst.year} (${signedPct(worst.ret)})`}
      />
      <div className="scrollbar-none -mx-5 overflow-x-auto px-5 sm:mx-0 sm:px-0">
        <table className="w-full min-w-[720px] border-separate border-spacing-1 text-center">
          <thead>
            <tr className="font-mono text-[10px] uppercase tracking-[0.06em] text-subtle">
              <th className="w-12 text-left font-medium" />
              {MONTHS.map((m) => (
                <th key={m} className="font-medium">
                  {m}
                </th>
              ))}
              <th className="w-16 font-medium">Year</th>
            </tr>
          </thead>
          <tbody>
            {years.map((y) => {
              const row = months.filter((m) => m.year === y);
              const yearRet = row.reduce((acc, m) => acc * (1 + m.ret), 1) - 1;
              return (
                <tr key={y}>
                  <td className="tabular pr-1 text-left text-[12px] font-medium text-muted">{y}</td>
                  {MONTHS.map((_, i) => {
                    const m = row.find((r) => r.month === i);
                    return (
                      <td key={i} className="h-10 rounded-md p-0" style={{ background: m ? heat(m.ret) : "transparent" }} title={m ? `${MONTHS[i]} ${y}: ${signedPct(m.ret)} (${signedMoney(m.gain)})` : undefined}>
                        {m && <span className="tabular text-[11px] font-medium text-foreground/90">{signedPct(m.ret, 1)}</span>}
                      </td>
                    );
                  })}
                  <td className="tabular rounded-md bg-surface-2 text-[12px] font-semibold">
                    <Signed value={yearRet} format={(v) => signedPct(v, 1)} />
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </Card>
  );
}

/* ------------------------- Return vs. time held --------------------------- */

export function ReturnVsTime({ points, avgDays }: { points: HoldingPoint[]; avgDays: number | null }) {
  const router = useRouter();
  const gains = points.filter((p) => p.ret >= 0);
  const losses = points.filter((p) => p.ret < 0);
  return (
    <Card className="min-w-0 p-5 sm:p-6">
      <SectionTitle title="Return vs. time held" subtitle={avgDays !== null ? `Value-weighted average hold: ${Math.round(avgDays)} days` : "How returns grow the longer you hold"} />
      <div className="h-[300px]">
        <ResponsiveContainer>
          <ScatterChart margin={{ top: 16, right: 0, bottom: 0, left: 0 }}>
            <CartesianGrid stroke="var(--chart-grid)" />
            <XAxis type="number" dataKey="days" name="Days held" tick={{ fill: "var(--subtle)", fontSize: 11 }} tickLine={false} axisLine={false} tickFormatter={(d: number) => (d >= 365 ? `${(d / 365).toFixed(1)}y` : `${d}d`)} />
            <YAxis type="number" dataKey="ret" orientation="right" width={1} tickLine={false} axisLine={false} tick={(props: object) => <InsideTick {...props} format={(v) => pct(v, 0)} />} />
            <ZAxis type="number" dataKey="value" range={[40, 600]} />
            <Tooltip
              cursor={false}
              content={({ active, payload }) => {
                const p = active && payload?.[0]?.payload as HoldingPoint | undefined;
                if (!p) return null;
                return (
                  <div className="rounded-xl border border-border bg-surface-3/95 px-3 py-2 text-[12px] shadow-xl backdrop-blur">
                    <p className="max-w-[200px] truncate font-medium">{p.name}</p>
                    <p className="tabular mt-0.5 text-muted">
                      {p.days} days · {money(p.value)} · <Signed value={p.ret} format={(v) => signedPct(v)} />
                    </p>
                  </div>
                );
              }}
            />
            {[
              { rows: gains, color: "var(--up)" },
              { rows: losses, color: "var(--down)" },
            ].map(({ rows, color }) => (
              <Scatter
                key={color}
                data={rows}
                fill={`color-mix(in srgb, ${color} 55%, transparent)`}
                stroke={color}
                strokeWidth={1}
                isAnimationActive={false}
                className="cursor-pointer"
                onClick={(d) => {
                  const key = (d as unknown as { payload?: HoldingPoint }).payload?.key;
                  if (key) router.push(`/product/${encodeURIComponent(key.split("|")[0])}`);
                }}
              />
            ))}
          </ScatterChart>
        </ResponsiveContainer>
      </div>
      <p className="mt-2 text-[12px] text-subtle">Bubble size is current value.</p>
    </Card>
  );
}

/* ---------------------------- By product type ----------------------------- */

export function TypeBreakdown({ groups }: { groups: GroupPerformance[] }) {
  const max = Math.max(...groups.map((g) => g.value), 1);
  return (
    <Card className="min-w-0 p-5 sm:p-6">
      <SectionTitle title="By product type" subtitle="Where the value sits, and how each type has done" />
      <ul className="space-y-3.5">
        {groups.map((g) => (
          <li key={g.name}>
            <div className="flex items-baseline justify-between gap-3 text-[13px]">
              <span className="truncate font-medium">
                {g.name} <span className="text-[12px] font-normal text-subtle">· {g.count}</span>
              </span>
              <span className="tabular shrink-0">
                {money(g.value)} <span className="ml-1.5 text-[12px]"><Signed value={g.ret} format={(v) => signedPct(v)} /></span>
              </span>
            </div>
            <div className="relative mt-1.5 h-2 overflow-hidden rounded-full bg-surface-2">
              {/* Cost basis underneath, value on top: the gap is the gain. */}
              <div className="absolute inset-y-0 left-0 rounded-full bg-foreground/15" style={{ width: `${(Math.min(g.cost, max) / max) * 100}%` }} />
              <div className="absolute inset-y-0 left-0 rounded-full" style={{ width: `${(g.value / max) * 100}%`, background: "linear-gradient(90deg, color-mix(in srgb, var(--cat-1) 45%, transparent), var(--cat-1))" }} />
            </div>
          </li>
        ))}
      </ul>
      <p className="mt-4 text-[12px] text-subtle">Faint bar: what you paid. Bright bar: what it&apos;s worth.</p>
    </Card>
  );
}

/* ------------------------------ Diversification --------------------------- */

export function Diversification({ c, holdings, top }: { c: Concentration; holdings: number; top: HoldingView[] }) {
  const effective = Math.max(1, Math.round(c.effective));
  const label = c.top1 > 0.4 ? "Concentrated" : c.top5 > 0.75 ? "Top-heavy" : "Well spread";
  return (
    <Card className="min-w-0 p-5 sm:p-6">
      <SectionTitle title="Diversification" subtitle={`${label}: your ${holdings} holdings behave like ${effective} equally sized ones`} />
      {/* Stacked share bar: the top five, then everything else. */}
      <div className="flex h-3 overflow-hidden rounded-full bg-surface-2">
        {top.map((h, i) => (
          <div
            key={h.key}
            className="h-full border-r border-surface"
            style={{ width: `${c.top1 && h.value ? (h.value / (top[0].value! / c.top1)) * 100 : 0}%`, background: `color-mix(in srgb, var(--cat-1) ${90 - i * 14}%, transparent)` }}
          />
        ))}
      </div>
      <ul className="mt-4 space-y-2">
        {top.map((h, i) => (
          <li key={h.key} className="flex items-center gap-2 text-[13px]">
            <span className="size-2.5 shrink-0 rounded-sm" style={{ background: `color-mix(in srgb, var(--cat-1) ${90 - i * 14}%, transparent)` }} />
            <Link href={`/product/${encodeURIComponent(h.identity.productId)}`} className="min-w-0 flex-1 truncate hover:underline">
              {h.product?.name ?? "Unknown"}
            </Link>
            <span className="tabular shrink-0 text-muted">{pct(h.value! / (top[0].value! / c.top1), 1)}</span>
          </li>
        ))}
      </ul>
      <dl className="mt-5 grid grid-cols-3 gap-2 border-t border-border pt-4">
        {[
          { label: "Top holding", value: pct(c.top1, 0) },
          { label: "Top 5", value: pct(c.top5, 0) },
          { label: "Effective", value: String(effective) },
        ].map((s) => (
          <div key={s.label}>
            <dt className="font-mono text-[10px] uppercase tracking-[0.06em] text-subtle">{s.label}</dt>
            <dd className={cn("tabular mt-1 text-[17px] font-semibold")}>{s.value}</dd>
          </div>
        ))}
      </dl>
    </Card>
  );
}
