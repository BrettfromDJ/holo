import { holdingKey, priceKey, type CollectionData, type HoldingIdentity, type ISODate, type PricePoint } from "../types";
import { addDays, daysBetween } from "./dates";

/**
 * A stored daily price is carried forward for at most this many days. Past
 * that, the price is treated as unknown rather than silently reused forever.
 */
export const MAX_CARRY_FORWARD_DAYS = 10;

export interface ResolvedPrice {
  price: number;
  /** Date of the observation actually used. */
  observedOn: ISODate;
  origin: "current" | "history" | "derived-24h" | "manual";
}

function lastAtOrBefore(points: PricePoint[], date: ISODate): PricePoint | null {
  let lo = 0;
  let hi = points.length - 1;
  let found: PricePoint | null = null;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (points[mid].date <= date) {
      found = points[mid];
      lo = mid + 1;
    } else hi = mid - 1;
  }
  return found;
}

/**
 * Answers "what was this holding worth per unit on date D?" using only real
 * observations: the current quote (for today), stored daily snapshots
 * (carried forward a bounded number of days), the source's own 24h change (to
 * recover yesterday's price), or a manual valuation for graded items.
 *
 * It never interpolates between observations and never invents a value: when
 * nothing is known it returns `null`.
 */
export class PriceResolver {
  constructor(
    private readonly data: Pick<CollectionData, "prices" | "history" | "manualValues">,
    private readonly today: ISODate,
  ) {}

  resolve(identity: HoldingIdentity, date: ISODate): ResolvedPrice | null {
    if (identity.grade) {
      const manual = this.data.manualValues[holdingKey(identity)];
      if (manual && manual.date <= date) return { price: manual.value, observedOn: manual.date, origin: "manual" };
      return null;
    }

    const key = priceKey(identity.productId, identity.printing);
    const current = this.data.prices[key];

    if (date >= this.today && current && current.market !== null && current.status !== "unavailable") {
      return { price: current.market, observedOn: this.today, origin: "current" };
    }

    const points = this.data.history[key];
    const p = points?.length ? lastAtOrBefore(points, date) : null;
    const stored = p && daysBetween(p.date, date) <= MAX_CARRY_FORWARD_DAYS ? p : null;

    // For yesterday, an exact snapshot wins; otherwise the source's own 24h
    // change is a better observation than a carried-forward older snapshot.
    if (date === addDays(this.today, -1) && stored?.date !== date) {
      const derived = this.derivedYesterday(key);
      if (derived !== null) return { price: derived, observedOn: date, origin: "derived-24h" };
    }

    if (stored) return { price: stored.price, observedOn: stored.date, origin: "history" };
    return null;
  }

  /** Yesterday's price recovered from the source's reported 24h % change. */
  private derivedYesterday(key: string): number | null {
    const current = this.data.prices[key];
    if (!current || current.market === null || current.change24hPct === null) return null;
    const factor = 1 + current.change24hPct / 100;
    if (factor <= 0) return null;
    return current.market / factor;
  }
}
