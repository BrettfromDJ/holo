/**
 * Our own 24-hour and 7-day price changes for catalog cards, from the daily prices we keep
 * (`catalog_price_days`, a rolling 8 days). The catalog sync's set pages come without TCG API's
 * changes, so most cards had none and could never show as risers; now any card the sync prices
 * gets them after a day (24 hours) or a week (7 days). Changes TCG API did send are kept.
 */

/** Days of daily prices kept (a 7-day change needs today and 7 days back, with a day's slack). */
export const PRICE_DAYS_KEPT = 9;

/** Prices from this up get a daily row: riser lists start higher ($10, $20), and this leaves room to cross them. */
export const PRICE_DAYS_MIN = 5;

export interface PriceDay {
  product_id: string;
  printing: string;
  day: string; // YYYY-MM-DD
  market: number;
}

interface ChangeRow {
  product_id: string;
  printing: string;
  market_price: number | null;
  change_24h_pct: number | null;
  change_7d_pct: number | null;
}

/** "YYYY-MM-DD", `days` before `day`. */
export function daysBefore(day: string, days: number): string {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - days);
  return d.toISOString().slice(0, 10);
}

const pct = (now: number, then: number) => Math.round(((now / then - 1) * 100) * 100) / 100;

/**
 * Fill each row's missing 24-hour and 7-day change from `history` (that card's earlier days):
 * 24 hours against the latest day 1 or 2 days back; 7 days against the day closest to a week
 * back, 6 to 8 days ago. Rows with a change already, without a price, or without a matching
 * day stay as they are.
 */
export function withOwnChanges<T extends ChangeRow>(rows: T[], history: PriceDay[], today: string): T[] {
  const byKey = new Map<string, Map<string, number>>();
  for (const h of history) {
    const key = `${h.product_id}|${h.printing}`;
    if (!byKey.has(key)) byKey.set(key, new Map());
    byKey.get(key)!.set(h.day, Number(h.market));
  }
  const pick = (days: Map<string, number>, offsets: number[]) => {
    for (const o of offsets) {
      const v = days.get(daysBefore(today, o));
      if (v !== undefined && v > 0) return v;
    }
    return undefined;
  };
  return rows.map((r) => {
    const days = byKey.get(`${r.product_id}|${r.printing}`);
    const now = r.market_price === null ? null : Number(r.market_price);
    if (!days || now === null || now <= 0) return r;
    const out = { ...r };
    if (out.change_24h_pct === null) {
      const then = pick(days, [1, 2]);
      if (then !== undefined) out.change_24h_pct = pct(now, then);
    }
    if (out.change_7d_pct === null) {
      const then = pick(days, [7, 6, 8]);
      if (then !== undefined) out.change_7d_pct = pct(now, then);
    }
    return out;
  });
}

/**
 * Whether a weekly move held: yesterday's price was already past the week-ago price in the same
 * direction, so the move isn't one odd sale today. Unknown (no days kept for the card) counts as
 * held: there's nothing to judge it by.
 */
export function moveHeld(days: PriceDay[], today: string, direction: "up" | "down"): boolean {
  const byDay = new Map(days.map((d) => [d.day, Number(d.market)]));
  const pick = (offsets: number[]) => {
    for (const o of offsets) {
      const v = byDay.get(daysBefore(today, o));
      if (v !== undefined && v > 0) return v;
    }
    return undefined;
  };
  const yesterday = pick([1, 2]);
  const weekAgo = pick([7, 6, 8]);
  if (yesterday === undefined || weekAgo === undefined) return true;
  return direction === "up" ? yesterday > weekAgo : yesterday < weekAgo;
}

/**
 * Whether eBay's recent sales back a card's market price: with at least 3 sold copies, a price
 * more than 40% off their median (either way) isn't trusted for the risers. Without enough sales,
 * there's nothing to check against: trusted.
 */
export function backedBySales(market: number | null, ebay: { median: number | null; count: number } | null | undefined): boolean {
  if (market === null || !ebay || ebay.median === null || ebay.count < 3 || ebay.median <= 0) return true;
  return Math.abs(market / ebay.median - 1) <= 0.4;
}
