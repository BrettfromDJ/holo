import {
  holdingKey,
  priceKey,
  type CollectionData,
  type HoldingIdentity,
  type ISODate,
  type Product,
  type ChartRange,
} from "../types";
import { addDays, eachDay, monthKey, rangeStart } from "./dates";
import {
  Ledger,
  buildLedger,
  costBasisOf,
  effectiveTransactions,
  quantityOf,
  realizedOf,
  acquisitionCost,
  type Lot,
  type RealizedEntry,
} from "./ledger";
import { PriceResolver, type ResolvedPrice } from "./prices";

export type HoldingCategory = "sealed" | "single" | "graded";

export interface HoldingView {
  key: string;
  identity: HoldingIdentity;
  product: Product | undefined;
  category: HoldingCategory;
  quantity: number;
  costBasis: number;
  avgCost: number;
  lots: Lot[];
  realizedGain: number;
  /** Per-unit market price, null when unknown. */
  price: number | null;
  priceOrigin: ResolvedPrice["origin"] | null;
  priceStatus: "live" | "stale" | "unavailable" | "manual";
  priceUpdatedAt: string | null;
  value: number | null;
  unrealized: number | null;
  unrealizedPct: number | null;
  /** Market-driven change since yesterday on units held yesterday. */
  dayChange: number | null;
  dayChangePct: number | null;
  /** Yesterday's value of the units held yesterday (denominator for day %). */
  prevDayValue: number | null;
  change7dPct: number | null;
  change30dPct: number | null;
  firstAcquired: ISODate | null;
  lastAcquired: ISODate | null;
}

export function categoryOf(identity: HoldingIdentity, product: Product | undefined): HoldingCategory {
  if (identity.grade) return "graded";
  return product?.kind === "sealed" ? "sealed" : "single";
}

/** Current holdings (quantity > 0) valued as of `today`. */
export function computeHoldings(data: CollectionData, today: ISODate): HoldingView[] {
  const ledger = buildLedger(data.transactions, today);
  const yesterdayLedger = buildLedger(data.transactions, addDays(today, -1));
  const resolver = new PriceResolver(data, today);
  const yesterday = addDays(today, -1);
  const out: HoldingView[] = [];

  for (const [key, pos] of ledger.positions) {
    const quantity = quantityOf(pos);
    if (quantity <= 0) continue;
    const product = data.products[pos.identity.productId];
    const costBasis = costBasisOf(pos);
    const resolved = resolver.resolve(pos.identity, today);
    const price = resolved?.price ?? null;
    const value = price === null ? null : price * quantity;
    const unrealized = value === null ? null : value - costBasis;

    const np = data.prices[priceKey(pos.identity.productId, pos.identity.printing)];
    let priceStatus: HoldingView["priceStatus"];
    if (pos.identity.grade) priceStatus = resolved ? "manual" : "unavailable";
    else if (!resolved) priceStatus = "unavailable";
    else if (resolved.origin === "current" && np?.status === "live") priceStatus = "live";
    else priceStatus = "stale";

    const prevPos = yesterdayLedger.positions.get(key);
    const prevQty = prevPos ? quantityOf(prevPos) : 0;
    const prevPrice = resolver.resolve(pos.identity, yesterday)?.price ?? null;
    let dayChange: number | null = null;
    let dayChangePct: number | null = null;
    let prevDayValue: number | null = null;
    if (price !== null && prevPrice !== null) {
      dayChange = prevQty * (price - prevPrice);
      dayChangePct = prevPrice > 0 ? (price - prevPrice) / prevPrice : null;
      prevDayValue = prevQty * prevPrice;
    }

    out.push({
      key,
      identity: pos.identity,
      product,
      category: categoryOf(pos.identity, product),
      quantity,
      costBasis,
      avgCost: costBasis / quantity,
      lots: pos.lots.map((l) => ({ ...l })),
      realizedGain: realizedOf(pos),
      price,
      priceOrigin: resolved?.origin ?? null,
      priceStatus,
      priceUpdatedAt: pos.identity.grade ? (resolved?.observedOn ?? null) : (np?.updatedAt ?? resolved?.observedOn ?? null),
      value,
      unrealized,
      unrealizedPct: unrealized === null || costBasis <= 0 ? null : unrealized / costBasis,
      dayChange,
      dayChangePct,
      prevDayValue,
      change7dPct: pos.identity.grade ? null : (np?.change7dPct ?? null),
      change30dPct: pos.identity.grade ? null : (np?.change30dPct ?? null),
      firstAcquired: pos.firstAcquired,
      lastAcquired: pos.lastAcquired,
    });
  }
  return out;
}

export interface TimelinePoint {
  date: ISODate;
  /** Market value of priced holdings at end of day. */
  value: number;
  /** Cost basis of all units held at end of day. */
  costBasis: number;
  /** Cost basis of the priced subset (pairs with `value`). */
  costBasisPriced: number;
  unrealized: number;
  /** Mark-to-market change on units held at the previous close. Excludes flows. */
  marketGain: number;
  /** Return for the day: marketGain / previous priced value of those units. */
  dailyReturn: number;
  /** Time-weighted return index, 1.0 at the first day. */
  twrIndex: number;
  /** Cumulative market gain since the first day. */
  cumulativeMarketGain: number;
  /** Cash paid into the collection on this day (purchases incl. fees). */
  invested: number;
  /** Cash received on this day (net sale proceeds). */
  proceeds: number;
  unpricedHoldings: number;
}

/**
 * Day-by-day replay of the collection.
 *
 * Daily dollar change is cash-flow adjusted: it only measures price movement
 * on units that were held at the previous close (Σ q₍t−1₎ · (p₍t₎ − p₍t−1₎)).
 * Buying a $1,000 box worth $1,000 raises `value` by $1,000 but contributes $0
 * to `marketGain`. Percentage performance chains daily returns into a
 * time-weighted return index, so contributions and withdrawals never show up
 * as performance.
 */
export function computeTimeline(data: CollectionData, today: ISODate): TimelinePoint[] {
  const txs = effectiveTransactions(data.transactions).filter((t) => t.date <= today);
  if (!txs.length) return [];
  const resolver = new PriceResolver(data, today);
  const ledger = new Ledger();
  const prevQty = new Map<string, number>();
  const prevPrice = new Map<string, number>();
  const points: TimelinePoint[] = [];
  let idx = 0;
  let twr = 1;
  let cumulative = 0;

  for (const day of eachDay(txs[0].date, today)) {
    let invested = 0;
    let proceeds = 0;
    while (idx < txs.length && txs[idx].date <= day) {
      const flow = ledger.apply(txs[idx++]);
      if (flow) {
        if (flow.cash > 0) invested += flow.cash;
        else proceeds += -flow.cash;
      }
    }

    let value = 0;
    let costBasis = 0;
    let costBasisPriced = 0;
    let gain = 0;
    let denom = 0;
    let unpriced = 0;
    const curQty = new Map<string, number>();
    const curPrice = new Map<string, number>();

    for (const [key, pos] of ledger.positions) {
      const q = quantityOf(pos);
      const qPrev = prevQty.get(key) ?? 0;
      if (q <= 0 && qPrev <= 0) continue;
      const price = resolver.resolve(pos.identity, day)?.price ?? null;

      if (q > 0) {
        const cb = costBasisOf(pos);
        costBasis += cb;
        if (price !== null) {
          value += q * price;
          costBasisPriced += cb;
        } else unpriced++;
        curQty.set(key, q);
      }
      if (price !== null) curPrice.set(key, price);

      const pPrev = prevPrice.get(key);
      if (qPrev > 0 && pPrev !== undefined && price !== null) {
        gain += qPrev * (price - pPrev);
        denom += qPrev * pPrev;
      }
    }

    const dailyReturn = denom > 0 ? gain / denom : 0;
    twr *= 1 + dailyReturn;
    cumulative += gain;
    points.push({
      date: day,
      value,
      costBasis,
      costBasisPriced,
      unrealized: value - costBasisPriced,
      marketGain: gain,
      dailyReturn,
      twrIndex: twr,
      cumulativeMarketGain: cumulative,
      invested,
      proceeds,
      unpricedHoldings: unpriced,
    });

    prevQty.clear();
    prevPrice.clear();
    for (const [k, v] of curQty) prevQty.set(k, v);
    for (const [k, v] of curPrice) prevPrice.set(k, v);
  }
  return points;
}

export interface RangePerformance {
  start: ISODate;
  end: ISODate;
  /** Sum of daily market gains after the start date (cash-flow adjusted). */
  marketGain: number;
  /** Time-weighted return over the range. */
  twr: number;
  startValue: number;
  endValue: number;
}

export function slicePoints(points: TimelinePoint[], range: ChartRange, today: ISODate): TimelinePoint[] {
  if (!points.length) return [];
  const start = rangeStart(range, today, points[0].date);
  const sliced = points.filter((p) => p.date >= start);
  return sliced.length ? sliced : points.slice(-1);
}

/** Performance between the first and last point of a slice. */
export function performanceOf(slice: TimelinePoint[]): RangePerformance | null {
  if (!slice.length) return null;
  const first = slice[0];
  const last = slice[slice.length - 1];
  const marketGain = slice.slice(1).reduce((s, p) => s + p.marketGain, 0);
  return {
    start: first.date,
    end: last.date,
    marketGain,
    twr: first.twrIndex > 0 ? last.twrIndex / first.twrIndex - 1 : 0,
    startValue: first.value,
    endValue: last.value,
  };
}

export interface PortfolioSummary {
  marketValue: number;
  /** Cost basis of everything currently held (the "Total Invested" metric). */
  costBasis: number;
  /** Cost basis of holdings that have a price. */
  costBasisPriced: number;
  unrealized: number;
  unrealizedPct: number | null;
  dayChange: number;
  dayChangePct: number | null;
  realized: number;
  holdingsCount: number;
  unitCount: number;
  unpricedCount: number;
  unpricedCostBasis: number;
}

export function summarize(holdings: HoldingView[], realized: number): PortfolioSummary {
  let marketValue = 0;
  let costBasis = 0;
  let costBasisPriced = 0;
  let dayChange = 0;
  let dayDenom = 0;
  let unitCount = 0;
  let unpricedCount = 0;
  let unpricedCostBasis = 0;
  for (const h of holdings) {
    costBasis += h.costBasis;
    unitCount += h.quantity;
    if (h.value === null) {
      unpricedCount++;
      unpricedCostBasis += h.costBasis;
      continue;
    }
    marketValue += h.value;
    costBasisPriced += h.costBasis;
    if (h.dayChange !== null && h.prevDayValue !== null) {
      dayChange += h.dayChange;
      dayDenom += h.prevDayValue;
    }
  }
  const unrealized = marketValue - costBasisPriced;
  return {
    marketValue,
    costBasis,
    costBasisPriced,
    unrealized,
    unrealizedPct: costBasisPriced > 0 ? unrealized / costBasisPriced : null,
    dayChange,
    dayChangePct: dayDenom > 0 ? dayChange / dayDenom : null,
    realized,
    holdingsCount: holdings.length,
    unitCount,
    unpricedCount,
    unpricedCostBasis,
  };
}

export function totalRealized(data: CollectionData, today: ISODate): { total: number; entries: RealizedEntry[] } {
  const ledger = buildLedger(data.transactions, today);
  const entries: RealizedEntry[] = [];
  for (const pos of ledger.positions.values()) entries.push(...pos.realized);
  entries.sort((a, b) => (a.date < b.date ? 1 : -1));
  return { total: entries.reduce((s, e) => s + e.gain, 0), entries };
}

/* ----------------------------- Analytics ----------------------------- */

export interface AllocationSlice {
  category: HoldingCategory;
  value: number;
  costBasis: number;
  share: number;
  count: number;
}

export function allocation(holdings: HoldingView[]): AllocationSlice[] {
  const cats: HoldingCategory[] = ["sealed", "single", "graded"];
  const total = holdings.reduce((s, h) => s + (h.value ?? 0), 0);
  return cats.map((category) => {
    const hs = holdings.filter((h) => h.category === category);
    const value = hs.reduce((s, h) => s + (h.value ?? 0), 0);
    return {
      category,
      value,
      costBasis: hs.reduce((s, h) => s + h.costBasis, 0),
      share: total > 0 ? value / total : 0,
      count: hs.length,
    };
  });
}

export interface SetPerformance {
  setName: string;
  value: number;
  costBasisPriced: number;
  unrealized: number;
  unrealizedPct: number | null;
  share: number;
  holdings: number;
}

export function performanceBySet(holdings: HoldingView[]): SetPerformance[] {
  const map = new Map<string, SetPerformance>();
  const total = holdings.reduce((s, h) => s + (h.value ?? 0), 0);
  for (const h of holdings) {
    const name = h.product?.setName ?? "Unknown set";
    const row = map.get(name) ?? { setName: name, value: 0, costBasisPriced: 0, unrealized: 0, unrealizedPct: null, share: 0, holdings: 0 };
    row.holdings++;
    if (h.value !== null) {
      row.value += h.value;
      row.costBasisPriced += h.costBasis;
      row.unrealized += h.value - h.costBasis;
    }
    map.set(name, row);
  }
  return [...map.values()]
    .map((r) => ({
      ...r,
      share: total > 0 ? r.value / total : 0,
      unrealizedPct: r.costBasisPriced > 0 ? r.unrealized / r.costBasisPriced : null,
    }))
    .sort((a, b) => b.value - a.value);
}

export interface MonthlyActivity {
  month: string;
  invested: number;
  proceeds: number;
}

export function monthlyActivity(data: CollectionData, today: ISODate): MonthlyActivity[] {
  const map = new Map<string, MonthlyActivity>();
  for (const t of effectiveTransactions(data.transactions)) {
    if (t.date > today) continue;
    const m = monthKey(t.date);
    const row = map.get(m) ?? { month: m, invested: 0, proceeds: 0 };
    if (t.type === "purchase" || (t.type === "adjustment" && t.quantity > 0)) row.invested += acquisitionCost(t);
    if (t.type === "sale") row.proceeds += t.quantity * t.unitPrice - t.fees - t.shipping - t.tax;
    map.set(m, row);
  }
  // Fill empty months so the chart has a continuous axis.
  const months = [...map.keys()].sort();
  if (!months.length) return [];
  const out: MonthlyActivity[] = [];
  let [y, mo] = months[0].split("-").map(Number);
  const last = monthKey(today);
  for (;;) {
    const key = `${y}-${String(mo).padStart(2, "0")}`;
    out.push(map.get(key) ?? { month: key, invested: 0, proceeds: 0 });
    if (key >= last) break;
    mo++;
    if (mo > 12) {
      mo = 1;
      y++;
    }
  }
  return out;
}

export function holdingIdentityKey(identity: HoldingIdentity): string {
  return holdingKey(identity);
}
