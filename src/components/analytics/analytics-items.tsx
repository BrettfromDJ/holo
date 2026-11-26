"use client";

import { ChevronDown } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { Area, Bar, BarChart, CartesianGrid, ComposedChart, Line, ReferenceLine, ResponsiveContainer, Scatter, ScatterChart, Treemap, Tooltip, XAxis, YAxis, ZAxis } from "recharts";
import { InsideTick } from "@/components/charts/inside-tick";
import { ProductImage } from "@/components/product/product-image";
import { DeltaPill } from "@/components/product/delta";
import { Chips, GlassStat, Heading, RowMore, toneOf } from "@/components/analytics/bits";
import { drawdownSeries, performanceByType, type Concentration, type HoldingPoint, type MonthReturn, type RiskStats } from "@/lib/finance/analytics";
import { performanceBySet, slicePoints, type HoldingView, type MonthlyActivity, type TimelinePoint } from "@/lib/finance/portfolio";
import { formatDate, formatMonth, formatShortDate, money, moneyCompact, signedMoney, signedPct } from "@/lib/format";
import type { ChartRange, ISODate } from "@/lib/types";
import { cn } from "@/lib/utils";

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const productHref = (id: string) => `/product/${encodeURIComponent(id)}`;

/** "12%" or "−3.4%", unsigned unless negative (the app's `percent`). */
export function percent(r: number | null | undefined, digits = 0): string {
  if (r === null || r === undefined) return "—";
  const v = `${(Math.abs(r) * 100).toFixed(digits)}%`;
  return r < -0.00005 ? `−${v}` : v;
}

/** A number colored by its sign (only the number). */
export function Signed({ value, format }: { value: number | null; format: (v: number) => string }) {
  if (value === null) return <span className="text-subtle">—</span>;
  return <span className={value >= 0 ? "text-up" : "text-down"}>{format(value)}</span>;
}

/** A surface card (the app's `.surface(radius: 16)`). */
function Surface({ className, children }: { className?: string; children: React.ReactNode }) {
  return <div className={cn("rounded-2xl border border-border bg-surface p-4", className)}>{children}</div>;
}

/* --------------------------------- History -------------------------------- */

type Mode = "value" | "return" | "drawdown";
type Span = Extract<ChartRange, "1M" | "3M" | "1Y" | "ALL">;
const PHRASE: Record<Span, string> = { "1M": "past month", "3M": "past 3 months", "1Y": "past year", ALL: "all time" };
const CAPTION: Record<Mode, string> = {
  value: "Dashed: what you paid. Hover to read a day.",
  return: "Price moves only; buying and selling don't count.",
  drawdown: "How far below its last high. 0% is a new high.",
};

/** The one chart: value, return or drawdown over a range, with the day under the pointer above it. */
export function HistorySection({ timeline, today }: { timeline: TimelinePoint[]; today: ISODate }) {
  const [mode, setMode] = useState<Mode>("value");
  const [range, setRange] = useState<Span>("1Y");
  const [hover, setHover] = useState<number | null>(null);

  const p = useMemo(() => {
    const slice = slicePoints(timeline, range, today);
    const base = slice[0]?.twrIndex || 1;
    const dd = drawdownSeries(slice);
    const days = slice.map((pt, i) => ({ date: pt.date, value: pt.value, cost: pt.costBasisPriced, ret: pt.twrIndex / base - 1, dd: dd[i].drawdown }));
    const gain = slice.slice(1).reduce((s, pt) => s + pt.marketGain, 0);
    return { days, gain, twr: days.at(-1)?.ret ?? 0 };
  }, [timeline, range, today]);

  const shown = hover !== null ? p.days[hover] : undefined;
  const key = mode === "value" ? "value" : mode === "return" ? "ret" : "dd";
  const tint = mode === "value" ? "var(--lime)" : mode === "drawdown" ? "var(--down)" : p.twr >= 0 ? "var(--up)" : "var(--down)";
  const gradient = `hist-${mode}`;

  return (
    <div className="space-y-3">
      <Chips label="Chart" value={mode} onChange={setMode} options={[{ value: "value", label: "Value" }, { value: "return", label: "Return" }, { value: "drawdown", label: "Drawdown" }]} />
      <p className="tabular flex h-6 items-center gap-2 text-[15px] font-medium">
        {shown ? (
          <>
            {mode === "value" ? <span>{money(shown.value)}</span> : mode === "return" ? <Signed value={shown.ret} format={(v) => signedPct(v)} /> : <span className={shown.dd < 0 ? "text-down" : ""}>{percent(shown.dd, 1)}</span>}
            <span className="text-muted">{formatDate(shown.date)}</span>
          </>
        ) : (
          <>
            <Signed value={p.gain} format={signedMoney} />
            <DeltaPill ratio={p.twr} />
            <span className="text-muted">{PHRASE[range]}</span>
          </>
        )}
      </p>
      {p.days.length > 1 ? (
        <div className="h-[240px] sm:h-[280px]">
          <ResponsiveContainer>
            <ComposedChart
              data={p.days}
              margin={{ top: 22, right: 0, left: 0, bottom: 0 }}
              onMouseMove={(s) => setHover(s?.activeTooltipIndex !== undefined && s?.activeTooltipIndex !== null ? Number(s.activeTooltipIndex) : null)}
              onMouseLeave={() => setHover(null)}
            >
              <defs>
                <linearGradient id={gradient} x1="0" y1={mode === "drawdown" ? "1" : "0"} x2="0" y2={mode === "drawdown" ? "0" : "1"}>
                  <stop offset="0%" stopColor={tint} stopOpacity={0.28} />
                  <stop offset="100%" stopColor={tint} stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid vertical={false} stroke="var(--chart-grid)" />
              <XAxis dataKey="date" hide />
              <YAxis
                orientation="right"
                width={1}
                tickLine={false}
                axisLine={false}
                domain={mode === "drawdown" ? ["auto", 0] : ["auto", "auto"]}
                tick={(props: object) => <InsideTick {...props} format={mode === "value" ? moneyCompact : (v) => percent(v, 0)} />}
              />
              {mode !== "value" && <ReferenceLine y={0} stroke="var(--border-strong)" />}
              <Tooltip cursor={{ stroke: "rgb(255 255 255 / 0.3)" }} content={() => null} />
              {mode === "value" && <Line type="monotone" dataKey="cost" stroke="var(--subtle)" strokeWidth={1.5} strokeDasharray="4 4" dot={false} activeDot={false} isAnimationActive={false} />}
              <Area type="monotone" dataKey={key} stroke={tint} strokeWidth={2.5} fill={`url(#${gradient})`} activeDot={{ r: 5, fill: tint, stroke: "var(--background)", strokeWidth: 2 }} isAnimationActive={false} />
            </ComposedChart>
          </ResponsiveContainer>
        </div>
      ) : (
        <p className="py-16 text-center text-[14px] text-muted">Not enough history yet.</p>
      )}
      <Chips label="Range" fill value={range} onChange={setRange} options={(["1M", "3M", "1Y", "ALL"] as Span[]).map((r) => ({ value: r, label: r === "ALL" ? "All" : r }))} />
      <p className="text-[12px] text-subtle">{CAPTION[mode]}</p>
    </div>
  );
}

/* ----------------------------- Winners & losers ---------------------------- */

export function WinnersLosers({ holdings }: { holdings: HoldingView[] }) {
  const [side, setSide] = useState<"gains" | "losses">("gains");
  const [rankBy, setRankBy] = useState<"dollar" | "percent">("dollar");
  const [showAll, setShowAll] = useState(false);
  const priced = holdings.filter((h) => h.unrealized !== null);
  const up = priced.filter((h) => h.unrealized! > 0).length;
  const key = (h: HoldingView) => (rankBy === "dollar" ? h.unrealized! : (h.unrealizedPct ?? 0));
  const all = side === "gains" ? priced.filter((h) => h.unrealized! > 0).sort((a, b) => key(b) - key(a)) : priced.filter((h) => h.unrealized! < 0).sort((a, b) => key(a) - key(b));
  const items = showAll ? all : all.slice(0, 5);

  return (
    <section className="space-y-3.5">
      <Heading title="Winners & losers" subtitle={priced.length ? `${up} of ${priced.length} in profit` : null} />
      <div className="flex items-center justify-between gap-2">
        <Chips
          label="Gains or losses"
          value={side}
          onChange={(v) => {
            setSide(v);
            setShowAll(false);
          }}
          options={[{ value: "gains", label: "Gains" }, { value: "losses", label: "Losses" }]}
        />
        <Chips label="Rank by" value={rankBy} onChange={setRankBy} options={[{ value: "dollar", label: "$" }, { value: "percent", label: "%" }]} />
      </div>
      <ul>
        {!items.length && <li className="py-4 text-[14px] text-muted">{side === "gains" ? "No holdings are in profit yet." : "Nothing is below cost."}</li>}
        {items.map((h, i) => (
          <li key={h.key} className={cn("flex items-center gap-1 py-2.5", i > 0 && "border-t border-border")}>
            <Link href={productHref(h.identity.productId)} className="flex min-w-0 flex-1 items-center gap-3">
              <ProductImage product={h.product} size="xs" grade={h.identity.grade} className="h-[50px] w-9 shrink-0 rounded-[3px]" />
              <div className="min-w-0 flex-1">
                <p className="truncate text-[15px] font-medium">{h.product?.name ?? "Unknown"}</p>
                <p className="tabular truncate text-[12px] text-muted">
                  {money(h.value)} value · {money(h.costBasis)} cost
                </p>
              </div>
              <span className={cn("tabular shrink-0 text-[15px] font-semibold", h.unrealized! >= 0 ? "text-up" : "text-down")}>{rankBy === "dollar" ? signedMoney(h.unrealized) : signedPct(h.unrealizedPct)}</span>
            </Link>
            <RowMore href={productHref(h.identity.productId)} label={`Open ${h.product?.name ?? "card"}`} />
          </li>
        ))}
      </ul>
      {all.length > 5 && (
        <button type="button" onClick={() => setShowAll((v) => !v)} className="text-[14px] font-medium text-muted hover:text-foreground">
          {showAll ? "Show fewer" : `Show all ${all.length}`}
        </button>
      )}
    </section>
  );
}

/* -------------------------------- Breakdown -------------------------------- */

/** One row: name ×count, value and its return, one quiet line, a thin bar. */
function BreakdownRow({ title, count, value, ret, line, fraction }: { title: string; count: number; value: number; ret: number | null; line: string; fraction: number }) {
  return (
    <li className="space-y-1.5 py-3">
      <div className="flex items-baseline gap-2">
        <p className="min-w-0 flex-1 truncate text-[14px] font-medium">
          {title} <span className="text-[12px] font-normal text-subtle">×{count}</span>
        </p>
        <span className="tabular text-[14px] font-semibold">{money(value)}</span>
        {ret !== null && Math.abs(ret) >= 0.0005 && <DeltaPill ratio={ret} className="text-[11px]" />}
      </div>
      <p className="tabular truncate text-[12px] text-muted">{line}</p>
      <div className="h-[3px] overflow-hidden rounded-full bg-surface-2">
        <div className="h-full origin-left animate-grow-x rounded-full" style={{ width: `${Math.max(fraction * 100, 1)}%`, background: (ret ?? 0) < 0 ? "var(--plan-pink)" : "var(--lime)" }} />
      </div>
    </li>
  );
}

export function Breakdown({ holdings }: { holdings: HoldingView[] }) {
  const [kind, setKind] = useState<"type" | "set" | "map">("type");
  const types = useMemo(() => performanceByType(holdings), [holdings]);
  const sets = useMemo(() => performanceBySet(holdings), [holdings]);
  const typeTotal = Math.max(
    types.reduce((s, g) => s + g.value, 0),
    1,
  );
  const typeMax = Math.max(...types.map((g) => g.value), 1);
  const setMax = Math.max(...sets.map((s) => s.share), 0.0001);
  return (
    <section className="space-y-3.5">
      <Heading title="Breakdown" />
      <Chips label="Break down by" value={kind} onChange={setKind} options={[{ value: "type", label: "Type" }, { value: "set", label: "Set" }, { value: "map", label: "Map" }]} />
      {kind === "type" && (
        <ul className="divide-y divide-border">
          {types.map((g) => (
            <BreakdownRow key={g.name} title={g.name} count={g.count} value={g.value} ret={g.ret} line={`${Math.round((g.value / typeTotal) * 100)}% of value · ${signedMoney(g.gain)}`} fraction={g.value / typeMax} />
          ))}
        </ul>
      )}
      {kind === "set" && (
        <ul className="divide-y divide-border">
          {sets.map((s) => (
            <BreakdownRow key={s.setName} title={s.setName} count={s.holdings} value={s.value} ret={s.unrealizedPct} line={`${percent(s.share, 0)} of value · ${signedMoney(s.unrealized)}`} fraction={s.share / setMax} />
          ))}
        </ul>
      )}
      {kind === "map" && <CollectionMap holdings={holdings} />}
    </section>
  );
}

/* ------------------------------ Collection map ---------------------------- */

interface MapNode {
  name: string;
  size: number;
  ret: number | null;
  href: string;
  [k: string]: unknown;
}

/** Gains beyond this show at full strength; losses (which stop at −100%) at LOSS_CAP. */
const MAP_CAP = 2;
const LOSS_CAP = 0.5;
function mapHeat(ret: number) {
  const t = Math.sqrt(Math.min(1, Math.abs(ret) / (ret >= 0 ? MAP_CAP : LOSS_CAP)));
  const strength = Math.round((0.08 + t * 0.42) * 100);
  return `color-mix(in srgb, ${ret >= 0 ? "var(--lime)" : "var(--plan-pink)"} ${strength}%, var(--surface-2))`;
}

/** Treemap: each holding sized by value, tinted by its return. Tap one to open it. */
function CollectionMap({ holdings }: { holdings: HoldingView[] }) {
  const router = useRouter();
  const data: MapNode[] = holdings
    .filter((h) => (h.value ?? 0) > 0)
    .sort((a, b) => (b.value ?? 0) - (a.value ?? 0))
    .slice(0, 40)
    .map((h) => ({ name: h.product?.name ?? "Unknown", size: h.value!, ret: h.unrealizedPct, href: productHref(h.identity.productId) }));
  if (!data.length) return null;
  return (
    <div className="pt-1">
      <div className="h-[360px] overflow-hidden rounded-xl sm:h-[420px]">
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
      <div className="mt-3 flex items-center gap-2 text-[11px] text-subtle">
        <span className="tabular">−{LOSS_CAP * 100}%</span>
        <span className="h-2 flex-1 rounded-full" style={{ background: `linear-gradient(90deg, ${mapHeat(-LOSS_CAP)}, ${mapHeat(0)}, ${mapHeat(MAP_CAP)})` }} />
        <span className="tabular">+{MAP_CAP * 100}%</span>
      </div>
    </div>
  );
}

function MapTile(props: { x?: number; y?: number; width?: number; height?: number; name?: string; size?: number; ret?: number | null; depth?: number }) {
  const { x = 0, y = 0, width = 0, height = 0, name, size, ret, depth } = props;
  if (depth === 0 || width < 2 || height < 2) return null;
  const showName = width >= 96 && height >= 52;
  const showValue = width >= 124 && height >= 84;
  return (
    <g className="cursor-pointer">
      <rect x={x + 1.5} y={y + 1.5} width={width - 3} height={height - 3} rx={6} fill={ret === null || ret === undefined ? "var(--surface-2)" : mapHeat(ret)} className="transition-opacity hover:opacity-80" />
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

/* --------------------------------- By month -------------------------------- */

/** Stronger color for bigger moves; square root so small moves still show. */
const cellHeat = (ret: number) => 0.14 + Math.sqrt(Math.min(1, Math.abs(ret) / 0.12)) * 0.86;

function MonthlyHeatmap({ months }: { months: MonthReturn[] }) {
  if (!months.length) return null;
  const years = [...new Set(months.map((m) => m.year))].sort((a, b) => b - a);
  return (
    <Surface className="space-y-5">
      {years.map((y) => {
        const row = months.filter((m) => m.year === y);
        const yearRet = row.reduce((acc, m) => acc * (1 + m.ret), 1) - 1;
        // Only months since you started (and up to now): no year of empty boxes.
        const first = Math.min(...row.map((m) => m.month));
        const last = y === years[0] ? Math.max(...row.map((m) => m.month)) : 11;
        const start = y === years[years.length - 1] ? first : 0;
        const span = Array.from({ length: last - start + 1 }, (_, i) => start + i);
        return (
          <div key={y} className="space-y-2">
            <div className="flex items-center justify-between">
              <span className="font-display text-[20px] leading-none">{y}</span>
              <DeltaPill ratio={yearRet} />
            </div>
            <div className="grid grid-cols-6 gap-[5px] sm:grid-cols-12">
              {span.map((i) => {
                const m = row.find((r) => r.month === i);
                const h = m ? cellHeat(m.ret) : 0;
                const dark = m && m.ret >= 0 && h > 0.45;
                return (
                  <div
                    key={i}
                    title={m ? `${MONTHS[i]} ${y}: ${signedPct(m.ret)} (${signedMoney(m.gain)})` : undefined}
                    className={cn("flex h-11 flex-col items-center justify-center gap-0.5 rounded-lg", dark ? "text-[#0b0b0c]" : m ? "text-foreground" : "text-subtle")}
                    style={{ background: m ? `color-mix(in srgb, ${m.ret >= 0 ? "var(--lime)" : "var(--plan-pink)"} ${Math.round(h * 100)}%, transparent)` : "rgb(255 255 255 / 0.03)" }}
                  >
                    <span className="font-mono text-[9px] uppercase opacity-70">{MONTHS[i]}</span>
                    <span className="tabular text-[11px] font-semibold">{m ? signedPct(m.ret, 1) : ""}</span>
                  </div>
                );
              })}
            </div>
          </div>
        );
      })}
    </Surface>
  );
}

export function ByMonth({ months, risk, activity }: { months: MonthReturn[]; risk: RiskStats; activity: MonthlyActivity[] }) {
  const short = (d: string | null | undefined) => (d ? formatShortDate(d) : "—");
  const up = months.filter((m) => m.ret > 0).length;
  return (
    <section className="space-y-3.5">
      <Heading title="By month" subtitle={months.length ? `${up} of ${months.length} months up` : null} />
      <MonthlyHeatmap months={months} />
      <div className="flex gap-2">
        <GlassStat label="Best day" value={signedMoney(risk.bestDay?.gain ?? null)} tone={toneOf(risk.bestDay?.gain)} />
        <GlassStat label="Worst day" value={signedMoney(risk.worstDay?.gain ?? null)} tone={toneOf(risk.worstDay?.gain)} />
        <GlassStat label="Biggest drop" value={percent(risk.maxDrawdown, 1)} tone={risk.maxDrawdown !== null && risk.maxDrawdown < -0.00005 ? "down" : undefined} />
      </div>
      {(risk.bestDay || risk.maxDrawdownTo) && (
        <p className="truncate text-[12px] text-subtle">
          Best {short(risk.bestDay?.date)} · worst {short(risk.worstDay?.date)}
          {risk.maxDrawdownTo ? ` · drop ${short(risk.maxDrawdownFrom)} → ${short(risk.maxDrawdownTo)}` : ""}
        </p>
      )}
      {activity.some((m) => m.invested > 0) && (
        <div className="space-y-2.5 pt-2.5">
          <p className="font-mono text-[11px] uppercase tracking-[0.1em] text-muted">Invested each month</p>
          <div className="h-[190px]">
            <ResponsiveContainer>
              <BarChart data={activity} margin={{ top: 22, right: 0, left: 0, bottom: 0 }}>
                <CartesianGrid vertical={false} stroke="var(--chart-grid)" />
                <XAxis dataKey="month" tick={{ fill: "var(--subtle)", fontSize: 11 }} tickLine={false} axisLine={false} tickFormatter={(m: string) => MONTHS[Number(m.slice(5, 7)) - 1] ?? m} minTickGap={12} />
                <YAxis orientation="right" width={1} tickLine={false} axisLine={false} tick={(props: object) => <InsideTick {...props} format={moneyCompact} />} />
                <Tooltip
                  cursor={{ fill: "rgb(255 255 255 / 0.04)" }}
                  content={({ active, payload }) => {
                    const m = active ? (payload?.[0]?.payload as MonthlyActivity | undefined) : undefined;
                    if (!m) return null;
                    return (
                      <div className="glass-panel tabular rounded-xl px-3 py-2 text-[12px]">
                        <p className="text-muted">{formatMonth(m.month)}</p>
                        <p className="mt-0.5 font-semibold">{money(m.invested)} invested</p>
                      </div>
                    );
                  }}
                />
                <Bar dataKey="invested" fill="var(--lime)" radius={[4, 4, 0, 0]} maxBarSize={28} isAnimationActive={false} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>
      )}
    </section>
  );
}

/* ------------------------------ Diversification --------------------------- */

export function Diversification({ c, holdings }: { c: Concentration; holdings: HoldingView[] }) {
  const top = holdings
    .filter((h) => (h.value ?? 0) > 0)
    .sort((a, b) => (b.value ?? 0) - (a.value ?? 0))
    .slice(0, 5);
  const total = holdings.reduce((s, h) => s + (h.value ?? 0), 0);
  if (total <= 0) return null;
  const effective = Math.max(1, Math.round(c.effective));
  const label = c.top1 > 0.4 ? "Concentrated" : c.top5 > 0.75 ? "Top-heavy" : "Well spread";
  const shade = (i: number) => `color-mix(in srgb, var(--plan-blue) ${95 - i * 15}%, transparent)`;
  return (
    <section className="space-y-3.5">
      <Heading title="Diversification" />
      <Surface className="space-y-3.5">
        <div className="flex items-center gap-3.5">
          <span className="tabular font-display text-[54px] leading-none text-lime">{effective}</span>
          <div className="min-w-0">
            <p className="text-[15px] font-semibold">{label}</p>
            <p className="text-[13px] text-muted">
              Your {holdings.length} holdings act like {effective} of equal&nbsp;size
            </p>
          </div>
        </div>
        <div className="flex h-3 gap-0.5 overflow-hidden rounded-full bg-surface-2">
          {top.map((h, i) => (
            <div key={h.key} className="h-full origin-left animate-grow-x" style={{ width: `${Math.max(1, ((h.value ?? 0) / total) * 100)}%`, background: shade(i) }} />
          ))}
        </div>
        <ul className="space-y-2">
          {top.map((h, i) => (
            <li key={h.key}>
              <Link href={productHref(h.identity.productId)} className="flex items-center gap-2.5 text-[13px] hover:underline">
                <span className="size-2.5 shrink-0 rounded-[3px]" style={{ background: shade(i) }} />
                <span className="min-w-0 flex-1 truncate">{h.product?.name ?? "Unknown"}</span>
                <span className="tabular shrink-0 font-semibold">{percent((h.value ?? 0) / total, 1)}</span>
              </Link>
            </li>
          ))}
        </ul>
        <div className="flex border-t border-border pt-3.5">
          {[
            { label: "Top holding", value: c.top1 },
            { label: "Top 5", value: c.top5 },
          ].map((s) => (
            <div key={s.label} className="flex-1">
              <p className="font-mono text-[10px] uppercase tracking-[0.1em] text-subtle">{s.label}</p>
              <p className="tabular mt-1 font-display text-[22px] leading-none">{percent(s.value, 0)}</p>
            </div>
          ))}
        </div>
      </Surface>
    </section>
  );
}

/* --------------------------------- Advanced -------------------------------- */

export function AdvancedStats({ risk, points, avgDays }: { risk: RiskStats; points: HoldingPoint[]; avgDays: number | null }) {
  const [open, setOpen] = useState(false);
  return (
    <section className="space-y-3.5">
      <button type="button" onClick={() => setOpen((v) => !v)} aria-expanded={open} className="flex w-full items-end justify-between gap-4 text-left">
        <Heading title="Advanced" subtitle="Time held, up days and volatility" />
        <ChevronDown className={cn("mb-1 size-4 shrink-0 text-muted transition-transform", open && "rotate-180")} />
      </button>
      {open && (
        <div className="grid animate-fade-in gap-3 lg:grid-cols-2">
          {points.length > 0 && <ReturnVsTime points={points} avgDays={avgDays} />}
          <div className="space-y-3">
            <AdvancedRow title="Up days" value={risk.upDays !== null ? `${Math.round(risk.upDays * 100)}%` : "—"} note="The share of days your collection's market value went up." />
            <AdvancedRow title="Volatility" value={risk.volatility !== null ? `${Math.round(risk.volatility * 100)}%` : "—"} note="How much the value swings, scaled to a year. Higher means bumpier." />
          </div>
        </div>
      )}
    </section>
  );
}

function AdvancedRow({ title, value, note }: { title: string; value: string; note: string }) {
  return (
    <Surface className="flex items-start gap-3 p-3.5">
      <div className="min-w-0 flex-1">
        <p className="text-[15px] font-semibold">{title}</p>
        <p className="mt-0.5 text-[12px] text-muted">{note}</p>
      </div>
      <span className="tabular font-display text-[22px] leading-none">{value}</span>
    </Surface>
  );
}

function ReturnVsTime({ points, avgDays }: { points: HoldingPoint[]; avgDays: number | null }) {
  const router = useRouter();
  const gains = points.filter((p) => p.ret >= 0);
  const losses = points.filter((p) => p.ret < 0);
  return (
    <Surface className="space-y-3 lg:row-span-2">
      <p className="text-[15px] font-semibold">Return vs. time held</p>
      {avgDays !== null && (
        <p className="flex items-baseline gap-1.5">
          <span className="tabular font-display text-[34px] leading-none">{Math.round(avgDays)}</span>
          <span className="text-[14px] text-muted">days, average hold</span>
        </p>
      )}
      <div className="h-[220px]">
        <ResponsiveContainer>
          <ScatterChart margin={{ top: 22, right: 0, bottom: 0, left: 0 }}>
            <CartesianGrid stroke="var(--chart-grid)" vertical={false} />
            <XAxis type="number" dataKey="days" tick={{ fill: "var(--subtle)", fontSize: 11 }} tickLine={false} axisLine={false} tickFormatter={(d: number) => `${d}d`} />
            <YAxis type="number" dataKey="ret" orientation="right" width={1} tickLine={false} axisLine={false} tick={(props: object) => <InsideTick {...props} format={(v) => percent(v, 0)} />} />
            <ZAxis type="number" dataKey="value" range={[30, 290]} />
            <ReferenceLine y={0} stroke="var(--border-strong)" />
            <Tooltip
              cursor={false}
              content={({ active, payload }) => {
                const p = active ? (payload?.[0]?.payload as HoldingPoint | undefined) : undefined;
                if (!p) return null;
                return (
                  <div className="glass-panel rounded-xl px-3 py-2 text-[12px]">
                    <p className="max-w-[200px] truncate font-medium">{p.name}</p>
                    <p className="tabular mt-0.5 text-muted">
                      Held {p.days} days · {money(p.value)} · <Signed value={p.ret} format={(v) => signedPct(v)} />
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
                fill={`color-mix(in srgb, ${color} 90%, transparent)`}
                isAnimationActive={false}
                className="cursor-pointer"
                onClick={(d) => {
                  const key = (d as unknown as { payload?: HoldingPoint }).payload?.key;
                  if (key) router.push(productHref(key.split("|")[0]));
                }}
              />
            ))}
          </ScatterChart>
        </ResponsiveContainer>
      </div>
    </Surface>
  );
}
