/**
 * Deal maker math for vendors at a show. A deal has two sides: what comes in
 * (the customer hands you) and what goes out (you hand them). Each side is
 * valued at a share of market ("rate"), unless a row's price was typed in.
 * Cash settles the difference.
 */

import { money } from "./format";

export type DealKind = "buy" | "sell" | "trade" | "empty";

/** Default rates, as a share of market value. */
export interface DealRates {
  /** What you pay for items you buy outright. */
  buy: number;
  /** What you credit for items taken in on trade. */
  trade: number;
  /** What you charge for items going out. */
  sell: number;
  /** Whether what comes in is added to your collection unless switched off per item (default on). */
  addIncoming?: boolean;
  /** Whether items going out that aren't in Holo ask what you paid (default on). */
  askCost?: boolean;
}

export const DEFAULT_RATES: DealRates = { buy: 0.7, trade: 0.8, sell: 1 };

export interface DealLine {
  /** Market value per unit, if known. */
  market: number | null;
  qty: number;
  /** Typed-in price per unit; overrides any rate. */
  price?: number | null;
  /** This line's own share of market, overriding the side's rate. */
  rate?: number | null;
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

/** The share of market a line counts at: its own rate if set, else the side's. */
export function lineRate(line: DealLine, sideRate: number) {
  return line.rate ?? sideRate;
}

/** Price per unit a line counts at: the typed price, else market × the line's rate. */
export function unitPrice(line: DealLine, sideRate: number): number | null {
  if (line.price !== undefined && line.price !== null) return line.price;
  return line.market === null ? null : round2(line.market * lineRate(line, sideRate));
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
  /** Outgoing lines with no known cost (not in Holo, no "you paid"): their profit is unknown. */
  uncosted: number;
  /**
   * What the deal leaves you ahead by: market value of what comes in, less your cost of what goes
   * out, less cash you pay (plus cash you get). Profit + value gained; it doesn't depend on how the
   * prices were split. Null when anything going out has no known cost, or the deal is empty.
   */
  ahead: number | null;
}

export function dealTotals(incoming: DealLine[], outgoing: DealLine[], rates: { in: number; out: number }): DealTotals {
  const inValue = round2(incoming.reduce((s, l) => s + lineTotal(l, rates.in), 0));
  const outValue = round2(outgoing.reduce((s, l) => s + lineTotal(l, rates.out), 0));
  const costed = outgoing.filter((l) => l.cost !== undefined && l.cost !== null);
  const profit = costed.length ? round2(costed.reduce((s, l) => s + lineTotal(l, rates.out) - (l.cost ?? 0), 0)) : null;
  const equity = round2(incoming.reduce((s, l) => s + (l.market === null ? 0 : l.market * l.qty) - lineTotal(l, rates.in), 0));
  const belowCost = costed.filter((l) => lineTotal(l, rates.out) < (l.cost ?? 0) - 0.005).length;
  const kind = dealKind(incoming.length, outgoing.length);
  const uncosted = outgoing.length - costed.length;
  // A pure buy has no profit (ahead = value gained); a pure sell has no value gained (ahead = profit).
  const ahead = kind === "empty" || uncosted > 0 ? null : round2((profit ?? 0) + equity);
  return { kind, inValue, outValue, balance: round2(outValue - inValue), profit, equity, belowCost, uncosted, ahead };
}

/** The ahead headline: "You come out ahead" (an open deal) or "You came out ahead" (a closed one). */
export function aheadTitle(n: number, past = false): string {
  if (Math.abs(n) < 0.005) return past ? "You broke even" : "You break even";
  return `You ${past ? "came" : "come"} out ${n > 0 ? "ahead" : "behind"}`;
}

/** What a closed deal keeps of its totals, for working out how far ahead it left you. */
export interface DealRecordTotals {
  kind: DealKind;
  profit: number | null;
  equity: number;
  /** Recorded since this was added; null when it couldn't be known. */
  ahead?: number | null;
  /** Recorded alongside `ahead`; its presence marks a record that knows its own ahead. */
  uncosted?: number;
}

/**
 * How far ahead a closed deal left you. Deals closed before it was recorded work it out from
 * profit + value gained (a buy is all value gained); a newer one with it unknown stays unknown.
 */
export function recordAhead(r: DealRecordTotals): number | null {
  if (r.ahead !== undefined && r.ahead !== null) return r.ahead;
  if (r.uncosted !== undefined) return null;
  if (r.kind === "buy") return round2(r.equity);
  if (r.profit === null || r.profit === undefined) return null;
  return round2(r.profit + (r.kind === "sell" ? 0 : r.equity));
}

/** Value taken in only means something when something comes in. */
export function showsEquity(t: DealTotals): boolean {
  return !(t.kind === "sell" || t.kind === "empty" || t.inValue === 0);
}

/**
 * How much better off you are after the deal, at market: your profit on what goes out plus
 * the value you gain on what comes in. Null when neither is known.
 */
export function dealNet(t: DealTotals): number | null {
  if (t.profit === null && !showsEquity(t)) return null;
  return round2((t.profit ?? 0) + (showsEquity(t) ? t.equity : 0));
}

/** "You come out $58 ahead", in plain English. */
export function dealVerdict(t: DealTotals): string | null {
  const n = dealNet(t);
  if (n === null) return null;
  if (Math.abs(n) < 0.005) return "You break even";
  return `You come out ${money(Math.abs(n))} ${n > 0 ? "ahead" : "behind"}`;
}

/** The cash rounded to the nearest $5, when it isn't already (null otherwise). */
export function roundedCash(balance: number): number | null {
  const r = Math.round(Math.abs(balance) / 5) * 5;
  if (r < 5 || Math.abs(Math.abs(balance) - r) <= 0.004) return null;
  return balance < 0 ? -r : r;
}

function round2(n: number) {
  return Math.round(n * 100) / 100;
}
