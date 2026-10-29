/**
 * Deal maker math for vendors at a show. A deal has two sides: what comes in
 * (the customer hands you) and what goes out (you hand them). Each side is
 * valued at a share of market ("rate"), unless a row's price was typed in.
 * Cash settles the difference.
 */

export type DealKind = "buy" | "sell" | "trade" | "empty";

/** Default rates, as a share of market value. */
export interface DealRates {
  /** What you pay for items you buy outright. */
  buy: number;
  /** What you credit for items taken in on trade. */
  trade: number;
  /** What you charge for items going out. */
  sell: number;
}

export const DEFAULT_RATES: DealRates = { buy: 0.7, trade: 0.8, sell: 1 };

export interface DealLine {
  /** Market value per unit, if known. */
  market: number | null;
  qty: number;
  /** Typed-in price per unit; overrides market × rate. */
  price?: number | null;
  /** Your cost for the units going out (out-lines only). */
  cost?: number | null;
}

export function dealKind(inCount: number, outCount: number): DealKind {
  if (inCount && outCount) return "trade";
  if (inCount) return "buy";
  if (outCount) return "sell";
  return "empty";
}

/** The rate each side starts at for this kind of deal. */
export function defaultSideRates(kind: DealKind, rates: DealRates) {
  return { in: kind === "trade" ? rates.trade : rates.buy, out: rates.sell };
}

/** Price per unit a line counts at: the typed price, else market × rate. */
export function unitPrice(line: DealLine, rate: number): number | null {
  if (line.price !== undefined && line.price !== null) return line.price;
  return line.market === null ? null : round2(line.market * rate);
}

export function lineTotal(line: DealLine, rate: number) {
  const p = unitPrice(line, rate);
  return p === null ? 0 : p * line.qty;
}

export interface DealTotals {
  kind: DealKind;
  /** What the incoming items count for. */
  inValue: number;
  /** What the outgoing items count for. */
  outValue: number;
  /** Positive: the customer pays you. Negative: you pay the customer. */
  balance: number;
  /** Profit on what goes out, against your cost. Null when no cost is known. */
  profit: number | null;
  /** Market value of what comes in, less what you're giving for it. */
  equity: number;
  /** Outgoing lines priced below your cost. */
  belowCost: number;
}

export function dealTotals(incoming: DealLine[], outgoing: DealLine[], rates: { in: number; out: number }): DealTotals {
  const inValue = round2(incoming.reduce((s, l) => s + lineTotal(l, rates.in), 0));
  const outValue = round2(outgoing.reduce((s, l) => s + lineTotal(l, rates.out), 0));
  const costed = outgoing.filter((l) => l.cost !== undefined && l.cost !== null);
  const profit = costed.length ? round2(costed.reduce((s, l) => s + lineTotal(l, rates.out) - (l.cost ?? 0), 0)) : null;
  const equity = round2(incoming.reduce((s, l) => s + (l.market === null ? 0 : l.market * l.qty) - lineTotal(l, rates.in), 0));
  const belowCost = costed.filter((l) => lineTotal(l, rates.out) < (l.cost ?? 0) - 0.005).length;
  return { kind: dealKind(incoming.length, outgoing.length), inValue, outValue, balance: round2(outValue - inValue), profit, equity, belowCost };
}

function round2(n: number) {
  return Math.round(n * 100) / 100;
}
