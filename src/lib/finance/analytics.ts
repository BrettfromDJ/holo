import { categoryOf as productCategory } from "../catalog";
import type { ISODate } from "../types";
import { daysBetween } from "./dates";
import type { HoldingView, TimelinePoint } from "./portfolio";

/**
 * Collection analytics computed from the day-by-day timeline and the current
 * holdings. Every return here is time-weighted (built from `twrIndex`), so
 * buying and selling never show up as performance.
 */

export interface RiskStats {
  /** Time-weighted return over the whole history. */
  totalReturn: number;
  /** That return per year, when the history spans at least ~3 months. */
  annualized: number | null;
  /** Standard deviation of daily returns, annualized. */
  volatility: number | null;
  /** Largest peak-to-trough fall of the return index (negative or 0). */
  maxDrawdown: number;
  maxDrawdownFrom: ISODate | null;
  maxDrawdownTo: ISODate | null;
  /** Current distance below the all-time high of the return index. */
  currentDrawdown: number;
  bestDay: { date: ISODate; gain: number } | null;
  worstDay: { date: ISODate; gain: number } | null;
  /** Share of days with a market gain, among days that moved. */
  upDays: number | null;
}

export function riskStats(points: TimelinePoint[]): RiskStats {
  const empty: RiskStats = { totalReturn: 0, annualized: null, volatility: null, maxDrawdown: 0, maxDrawdownFrom: null, maxDrawdownTo: null, currentDrawdown: 0, bestDay: null, worstDay: null, upDays: null };
  if (points.length < 2) return empty;
  const first = points[0];
  const last = points[points.length - 1];
  const totalReturn = first.twrIndex > 0 ? last.twrIndex / first.twrIndex - 1 : 0;
  const days = daysBetween(first.date, last.date);
  const annualized = days >= 90 ? Math.pow(1 + totalReturn, 365 / days) - 1 : null;

  const rets = points.slice(1).map((p) => p.dailyReturn);
  const mean = rets.reduce((s, r) => s + r, 0) / rets.length;
  const variance = rets.reduce((s, r) => s + (r - mean) ** 2, 0) / Math.max(1, rets.length - 1);
  const volatility = rets.length >= 20 ? Math.sqrt(variance) * Math.sqrt(365) : null;

  let peak = first.twrIndex;
  let peakDate = first.date;
  let maxDrawdown = 0;
  let from: ISODate | null = null;
  let to: ISODate | null = null;
  for (const p of points) {
    if (p.twrIndex > peak) {
      peak = p.twrIndex;
      peakDate = p.date;
    }
    const dd = peak > 0 ? p.twrIndex / peak - 1 : 0;
    if (dd < maxDrawdown) {
      maxDrawdown = dd;
      from = peakDate;
      to = p.date;
    }
  }
  const currentDrawdown = peak > 0 ? last.twrIndex / peak - 1 : 0;

  let bestDay: RiskStats["bestDay"] = null;
  let worstDay: RiskStats["worstDay"] = null;
  let up = 0;
  let moved = 0;
  for (const p of points.slice(1)) {
    if (Math.abs(p.marketGain) < 0.005) continue;
    moved++;
    if (p.marketGain > 0) up++;
    if (!bestDay || p.marketGain > bestDay.gain) bestDay = { date: p.date, gain: p.marketGain };
    if (!worstDay || p.marketGain < worstDay.gain) worstDay = { date: p.date, gain: p.marketGain };
  }
  return { totalReturn, annualized, volatility, maxDrawdown, maxDrawdownFrom: from, maxDrawdownTo: to, currentDrawdown, bestDay, worstDay, upDays: moved ? up / moved : null };
}

/** Drawdown series: how far below its running high the return index is on each day. */
export function drawdownSeries(points: TimelinePoint[]): { date: ISODate; drawdown: number }[] {
  let peak = 0;
  return points.map((p) => {
    peak = Math.max(peak, p.twrIndex);
    return { date: p.date, drawdown: peak > 0 ? p.twrIndex / peak - 1 : 0 };
  });
}

export interface MonthReturn {
  year: number;
  /** 0-11 */
  month: number;
  /** Time-weighted return for the month. */
  ret: number;
  /** Market gain in dollars for the month. */
  gain: number;
}

/** Return for each calendar month in the history (partial first and last months included). */
export function monthlyReturns(points: TimelinePoint[]): MonthReturn[] {
  const out: MonthReturn[] = [];
  let start: TimelinePoint | null = null;
  let prevEnd: TimelinePoint | null = null;
  let gain = 0;
  let key = "";
  const flush = (end: TimelinePoint) => {
    const base = prevEnd ?? start!;
    out.push({ year: Number(key.slice(0, 4)), month: Number(key.slice(5, 7)) - 1, ret: base.twrIndex > 0 ? end.twrIndex / base.twrIndex - 1 : 0, gain });
  };
  for (let i = 0; i < points.length; i++) {
    const p = points[i];
    const k = p.date.slice(0, 7);
    if (k !== key) {
      if (start) {
        flush(points[i - 1]);
        prevEnd = points[i - 1];
      }
      key = k;
      start = p;
      gain = 0;
    }
    if (i > 0) gain += p.marketGain;
  }
  if (start) flush(points[points.length - 1]);
  return out;
}

export interface Concentration {
  /** Share of value in the single largest holding. */
  top1: number;
  /** Share of value in the five largest holdings. */
  top5: number;
  /** "Effective number of holdings" (1 / Σ share²): how many equal holdings this behaves like. */
  effective: number;
}

export function concentration(holdings: HoldingView[]): Concentration {
  const values = holdings.map((h) => h.value ?? 0).filter((v) => v > 0).sort((a, b) => b - a);
  const total = values.reduce((s, v) => s + v, 0);
  if (!total) return { top1: 0, top5: 0, effective: 0 };
  const shares = values.map((v) => v / total);
  return { top1: shares[0], top5: shares.slice(0, 5).reduce((s, x) => s + x, 0), effective: 1 / shares.reduce((s, x) => s + x * x, 0) };
}

export interface GroupPerformance {
  name: string;
  value: number;
  cost: number;
  gain: number;
  ret: number | null;
  count: number;
}

/** Value and unrealized return grouped by product type (Booster Box, ETB, Card…). */
export function performanceByType(holdings: HoldingView[]): GroupPerformance[] {
  const groups = new Map<string, GroupPerformance>();
  for (const h of holdings) {
    if (h.value === null || !h.product) continue;
    const name = h.identity.grade ? "Graded card" : productCategory(h.product);
    const g = groups.get(name) ?? { name, value: 0, cost: 0, gain: 0, ret: null, count: 0 };
    g.value += h.value;
    g.cost += h.costBasis;
    g.count += 1;
    groups.set(name, g);
  }
  return [...groups.values()]
    .map((g) => ({ ...g, gain: g.value - g.cost, ret: g.cost > 0 ? (g.value - g.cost) / g.cost : null }))
    .sort((a, b) => b.value - a.value);
}

export interface HoldingPoint {
  key: string;
  name: string;
  /** Days since first bought. */
  days: number;
  ret: number;
  value: number;
}

/** Each priced holding's return against how long it has been held. */
export function returnVsTime(holdings: HoldingView[], today: ISODate): HoldingPoint[] {
  return holdings
    .filter((h) => h.unrealizedPct !== null && h.value !== null && h.firstAcquired)
    .map((h) => ({ key: h.key, name: h.product?.name ?? "Unknown", days: Math.max(0, daysBetween(h.firstAcquired!, today)), ret: h.unrealizedPct!, value: h.value! }));
}

/** Average days held, weighted by current value. */
export function averageHoldDays(points: HoldingPoint[]): number | null {
  const total = points.reduce((s, p) => s + p.value, 0);
  return total ? points.reduce((s, p) => s + p.days * p.value, 0) / total : null;
}
