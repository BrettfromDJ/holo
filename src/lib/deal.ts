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
  /** What "Round up" rounds the cash up to the next multiple of, in dollars (one of ROUND_STEPS; default $5). */
  roundStep?: number | null;
}

export const DEFAULT_RATES: DealRates = { buy: 0.7, trade: 0.8, sell: 1 };

/** The steps "Round up" can round the cash to (deal settings), and the one it starts at. */
export const ROUND_STEPS = [1, 5, 10, 25, 50, 100] as const;
export const DEFAULT_ROUND_STEP = 5;

/** The step the cash rounds up to: the saved one when it's one of ROUND_STEPS, else $5. */
export function roundStep(rates: Pick<DealRates, "roundStep">): number {
  const s = rates.roundStep;
  return typeof s === "number" && (ROUND_STEPS as readonly number[]).includes(s) ? s : DEFAULT_ROUND_STEP;
}

/** How far a side's % of market can go: the counter-offer slider's range. */
export const RATE_RANGE = { min: 0.4, max: 1.2 } as const;

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
  /** The catalog's market price, kept when the market was changed by hand (the app's "Reset to catalog price"). */
  catalogMarket?: number | null;
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
  /** Market value of what comes in / goes out (items without a market count as $0). */
  inMarket: number;
  outMarket: number;
}

/** Market value of some lines (items without a market count as $0). */
export function marketOf(lines: Pick<DealLine, "market" | "qty">[]): number {
  return round2(lines.reduce((s, l) => s + (l.market ?? 0) * l.qty, 0));
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
  return { kind, inValue, outValue, balance: round2(outValue - inValue), profit, equity, belowCost, uncosted, ahead, inMarket: marketOf(incoming), outMarket: marketOf(outgoing) };
}

/** The ahead headline: "You make a profit" (an open deal) or "You made a profit" (a closed one). Same as the app's dealAheadTitle. */
export function aheadTitle(n: number, past = false): string {
  if (Math.abs(n) < 0.005) return past ? "You broke even" : "You break even";
  if (n > 0) return past ? "You made a profit" : "You make a profit";
  return past ? "You took a loss" : "You take a loss";
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
export function showsEquity(t: Pick<DealTotals, "kind" | "inValue">): boolean {
  return !(t.kind === "sell" || t.kind === "empty" || t.inValue === 0);
}

/**
 * How much better off you are after the deal, at market: your profit on what goes out plus
 * the value you gain on what comes in. Null when neither is known.
 */
export function dealNet(t: Pick<DealTotals, "kind" | "inValue" | "profit" | "equity">): number | null {
  if (t.profit === null && !showsEquity(t)) return null;
  return round2((t.profit ?? 0) + (showsEquity(t) ? t.equity : 0));
}

/** "You come out $58 ahead", in plain English. */
export function dealVerdict(t: Pick<DealTotals, "kind" | "inValue" | "profit" | "equity">): string | null {
  const n = dealNet(t);
  if (n === null) return null;
  if (Math.abs(n) < 0.005) return "You break even";
  return `You come out ${money(Math.abs(n))} ${n > 0 ? "ahead" : "behind"}`;
}

/**
 * The cash rounded up to the next multiple of `step` dollars ($1,151.20 → $1,155 at $5), keeping
 * who pays whom (the sign). Null when it's already on a multiple, or there's no cash. Same as the
 * app's roundedCash(_:step:).
 */
export function roundedCash(balance: number, step: number = DEFAULT_ROUND_STEP): number | null {
  const cents = Math.round(Math.abs(balance) * 100);
  const stepCents = Math.round(step * 100);
  if (!Number.isFinite(cents) || cents === 0 || stepCents <= 0 || cents % stepCents === 0) return null;
  const r = (Math.ceil(cents / stepCents) * stepCents) / 100;
  return balance < 0 ? -r : r;
}

/* ------------------------------ Agreed cash ------------------------------- */

/** A deal adjusted to an agreed cash figure (see agreedDeal). */
export interface AgreedDeal<T extends DealLine> {
  incoming: T[];
  outgoing: T[];
  /** The side whose prices moved to reach the agreed cash; null when nothing was adjusted. */
  side: "in" | "out" | null;
  /** That side's priced total as a share of its market value (0.74 = 74% of market), when known. */
  share: number | null;
}

/**
 * The deal as it works out at an agreed cash figure (signed like `balance`). The difference from
 * the normal cash is spread across the going-out lines (or, with nothing going out, the coming-in
 * lines) in proportion to each line's total, never taking a line below $0 (then it gets as close
 * as it can). Exact to the cent: any leftover cent goes on the biggest line. The adjusted lines
 * carry their new price per unit; the stored deal is never changed. Same math as the app's
 * DealState.agreed(rates:).
 */
export function agreedDeal<T extends DealLine>(incoming: T[], outgoing: T[], rates: { in: number; out: number }, agreedCash: number | null | undefined): AgreedDeal<T> {
  const none: AgreedDeal<T> = { incoming, outgoing, side: null, share: null };
  if (agreedCash === null || agreedCash === undefined || !Number.isFinite(agreedCash)) return none;
  if (!incoming.length && !outgoing.length) return none;
  const side = outgoing.length ? "out" : "in";
  const lines = side === "out" ? outgoing : incoming;
  const r = side === "out" ? rates.out : rates.in;
  const cents = lines.map((l) => {
    const p = unitPrice(l, r);
    return p === null ? null : Math.max(0, Math.round(p * l.qty * 100));
  });
  const priced = cents.flatMap((c, i) => (c === null ? [] : [i]));
  if (!priced.length) return none;
  const balance = dealTotals(incoming, outgoing, rates).balance;
  const delta = Math.round((agreedCash - balance) * 100);
  const current = priced.reduce((s, i) => s + (cents[i] ?? 0), 0);
  const target = Math.max(0, current + (side === "out" ? delta : -delta));
  // Each line's share of the move: its total, or an even split when every line is at $0.
  const weight = (i: number) => (current > 0 ? (cents[i] ?? 0) : 1);
  const totalWeight = priced.reduce((s, i) => s + weight(i), 0);
  const next = new Map<number, number>();
  for (const i of priced) next.set(i, Math.floor((target * weight(i)) / totalWeight + 1e-6));
  const biggest = priced.reduce((b, i) => (weight(i) > weight(b) ? i : b), priced[0]);
  const spread = [...next.values()].reduce((s, n) => s + n, 0);
  next.set(biggest, (next.get(biggest) ?? 0) + target - spread);
  const adjusted = lines.map((l, i) => {
    const c = next.get(i);
    return c === undefined ? l : { ...l, price: c / 100 / l.qty, rate: null };
  });
  const marketCents = priced.reduce((s, i) => s + (lines[i].market === null ? 0 : lines[i].market! * lines[i].qty * 100), 0);
  const marketPriced = priced.reduce((s, i) => s + (lines[i].market === null ? 0 : next.get(i) ?? 0), 0);
  const share = marketCents > 0 ? marketPriced / marketCents : null;
  return side === "out" ? { incoming, outgoing: adjusted, side, share } : { incoming: adjusted, outgoing, side, share };
}

/** What decides a deal's prices: each side's rate and every line's key, quantity, % and price. */
interface PricedDeal {
  in: DealLineKeyed[];
  out: DealLineKeyed[];
  rateIn?: number | null;
  rateOut?: number | null;
}
interface DealLineKeyed {
  key: string;
  qty: number;
  price?: number | null;
  rate?: number | null;
}

/**
 * Whether a change renegotiates the deal (a side's % moved, a line's % or price or quantity
 * changed, a line added or removed), which lets go of an agreed cash figure. Same as the app's
 * DealState.renegotiates(from:).
 */
export function renegotiates(before: PricedDeal, after: PricedDeal): boolean {
  const sig = (items: DealLineKeyed[]) => items.map((i) => `${i.key}|${i.qty}|${i.price ?? "-"}|${i.rate ?? "-"}`).join("\n");
  return (before.rateIn ?? null) !== (after.rateIn ?? null) || (before.rateOut ?? null) !== (after.rateOut ?? null) || sig(before.in) !== sig(after.in) || sig(before.out) !== sig(after.out);
}

/** A line that follows its side's % (no typed price, no % of its own, a known market). */
function followsSideRate(l: DealLine) {
  return (l.price === undefined || l.price === null) && (l.rate === undefined || l.rate === null) && l.market !== null;
}

/**
 * The side's % of market that brings the cash to `cash` (signed like `balance`): what goes out
 * when anything does, else what comes in (the side agreedDeal moves). The cash is linear in that
 * rate for the lines that follow it (typed prices and lines with their own % stay put), so it's
 * solved exactly, then held to the slider's range. Null when the deal is empty or no line follows
 * the side's %. Same as the app's DealState.rate(forCash:rates:).
 */
export function rateForCash(incoming: DealLine[], outgoing: DealLine[], rates: { in: number; out: number }, cash: number, range: { min: number; max: number } = RATE_RANGE): { side: "in" | "out"; rate: number } | null {
  if (!Number.isFinite(cash) || (!incoming.length && !outgoing.length)) return null;
  const side = outgoing.length ? "out" : "in";
  const lines = side === "out" ? outgoing : incoming;
  const market = lines.reduce((s, l) => s + (followsSideRate(l) ? l.market! * l.qty : 0), 0);
  if (!(market > 0)) return null;
  const fixed = lines.reduce((s, l) => s + (followsSideRate(l) ? 0 : lineTotal(l, side === "out" ? rates.out : rates.in)), 0);
  const other = side === "out" ? incoming.reduce((s, l) => s + lineTotal(l, rates.in), 0) : outgoing.reduce((s, l) => s + lineTotal(l, rates.out), 0);
  // balance = out − in; only `market × rate` moves.
  const exact = side === "out" ? (cash + other - fixed) / market : (other - cash - fixed) / market;
  const rate = Math.min(range.max, Math.max(range.min, exact));
  return { side, rate: Math.round(rate * 1e6) / 1e6 };
}

/** What setting a cash amount changes: a side's rate and the agreed cash. */
interface CashDeal {
  in: DealLine[];
  out: DealLine[];
  rateIn?: number | null;
  rateOut?: number | null;
  agreedCash?: number | null;
}

/**
 * The deal at a cash amount the two of you settled on (signed like `balance`): the side's slider
 * moves to the rate that gets there (rateForCash), and the agreed cash is set to it as well, so it
 * lands exactly to the cent even where the slider's range or fixed prices stop short (agreedDeal
 * spreads the rest). `rates` are the rates each side is at now. Apply it straight to the deal, not
 * as an edit that renegotiates (which would let the agreed cash go again). Same as the app's
 * DealState.agreeing(cash:rates:).
 */
export function withAgreedCash<D extends CashDeal>(deal: D, rates: { in: number; out: number }, cash: number): D {
  const amount = round2(cash);
  const r = rateForCash(deal.in, deal.out, rates, amount);
  if (!r) return { ...deal, agreedCash: amount };
  return { ...deal, [r.side === "out" ? "rateOut" : "rateIn"]: r.rate, agreedCash: amount };
}

/**
 * The agreed cash for a typed amount: who pays whom stays as it is now (the sign of the balance);
 * when the cash is even, the customer pays you only if what goes out is worth more than what comes in.
 */
export function signedAgreedCash(amount: number, totals: Pick<DealTotals, "balance" | "inValue" | "outValue">): number {
  const a = round2(Math.abs(amount));
  const customerPays = Math.abs(totals.balance) < 0.005 ? totals.outValue > totals.inValue : totals.balance > 0;
  return customerPays ? a : -a;
}

function round2(n: number) {
  return Math.round(n * 100) / 100;
}

/* ------------------------- Parked deals and history ------------------------- */

/** "Deal at 3:42 PM": the name a parked deal gets when you don't type one. */
export function parkedDealName(at: Date): string {
  const h = at.getHours();
  const m = at.getMinutes();
  return `Deal at ${h % 12 === 0 ? 12 : h % 12}:${String(m).padStart(2, "0")} ${h < 12 ? "AM" : "PM"}`;
}

/** What a closed deal keeps that the history's day totals and search read. */
export interface DealHistoryRecord extends DealRecordTotals {
  at: string;
  /** Positive: the customer paid you. Negative: you paid the customer. */
  balance: number;
  notes?: string | null;
  lines?: { product: { name: string } }[];
}

/** A day's closed deals in numbers: how many, cash in and out, net cash, how far ahead and sale profit. */
export interface DealDayTotals {
  deals: number;
  /** Cash customers paid you. */
  cashIn: number;
  /** Cash you paid customers. */
  cashOut: number;
  /** Cash in less cash out. */
  net: number;
  /** How far ahead the day's deals left you, from the deals that know it; null when none do. */
  ahead: number | null;
  /** Sale profit, from the deals that have one; null when none do. */
  profit: number | null;
}

export function dealDayTotals(records: DealHistoryRecord[]): DealDayTotals {
  const cashIn = round2(records.reduce((s, r) => s + Math.max(0, r.balance), 0));
  const cashOut = round2(records.reduce((s, r) => s + Math.max(0, -r.balance), 0));
  const known = records.map(recordAhead).filter((n): n is number => n !== null);
  const profits = records.map((r) => r.profit).filter((n): n is number => n !== null && n !== undefined);
  return {
    deals: records.length,
    cashIn,
    cashOut,
    net: round2(cashIn - cashOut),
    ahead: known.length ? round2(known.reduce((s, n) => s + n, 0)) : null,
    profit: profits.length ? round2(profits.reduce((s, n) => s + n, 0)) : null,
  };
}

/** Words a deal of each kind answers to in the history search. */
const KIND_WORDS: Record<DealKind, string> = {
  buy: "buy buying bought",
  sell: "sale sell selling sold",
  trade: "trade trading traded",
  empty: "deal",
};

/**
 * Whether a closed deal matches the history search: every word typed must be found in one of its
 * cards' names, its notes, or its kind ("buy", "sale", "trade"). An empty search matches everything.
 */
export function matchesDealSearch(r: DealHistoryRecord, query: string): boolean {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  if (!words.length) return true;
  const text = [...(r.lines ?? []).map((l) => l.product.name), r.notes ?? "", KIND_WORDS[r.kind]].join(" \n ").toLowerCase();
  return words.every((w) => text.includes(w));
}

/* ------------------------- Agreed market and rounding ------------------------- */

/**
 * A side's lines at the market value the two of you agreed on: `total` shared across the lines in
 * proportion to their market prices, each keeping its catalog price in `catalogMarket` (cleared
 * once it's back on it), so it can be put back. Lines at a % of market re-price with it; typed
 * prices stay. Unchanged when the side has no market value or the total isn't positive. Same as
 * the app's DealStore.setAgreedMarket(_:on:).
 */
export function withAgreedMarket<T extends DealLine>(items: T[], total: number): T[] {
  const current = items.reduce((s, l) => s + (l.market ?? 0) * l.qty, 0);
  if (!(current > 0) || !(total > 0)) return items;
  const factor = total / current;
  return items.map((l) => {
    if (l.market === null || l.market === undefined) return l;
    const catalog = l.catalogMarket ?? l.market;
    const next = round2(l.market * factor);
    return { ...l, market: next, catalogMarket: Math.abs(next - catalog) < 0.005 ? null : catalog };
  });
}

/** Every line back on its catalog market price (the app's DealStore.resetMarket(on:)). */
export function withCatalogMarket<T extends DealLine>(items: T[]): T[] {
  return items.map((l) => (l.catalogMarket === null || l.catalogMarket === undefined ? l : { ...l, market: l.catalogMarket, catalogMarket: null }));
}

/** Whether a side's market value was changed by hand (any line keeps its catalog price aside). */
export function marketAgreed(items: DealLine[]): boolean {
  return items.some((l) => l.catalogMarket !== null && l.catalogMarket !== undefined);
}

/**
 * A market price typed for one line (the card sheet): the catalog's is remembered the first time
 * it changes and forgotten once it's back on it. Same as the app's DealCardSheet.applyMarket.
 */
export function withTypedMarket<T extends DealLine>(item: T, typed: number | null): T {
  if (typed === null || !Number.isFinite(typed)) return item;
  const catalog = item.catalogMarket ?? item.market;
  const catalogMarket = catalog !== null && catalog !== undefined && Math.abs(typed - catalog) < 0.005 ? null : (item.catalogMarket ?? item.market);
  return { ...item, market: typed, catalogMarket };
}

/** A side's % back on a whole number (settling on a total moved it to a fraction, e.g. 99.62%). */
export function wholeRate(r: number | null | undefined): number | null {
  return r === null || r === undefined ? null : Math.round(r * 100) / 100;
}

/**
 * The deal without its rounding: no agreed total, each side's % back on a whole number. What the
 * cards come to on their own (what Round up rounds), and what "Reset" / "Undo round" goes back to.
 * Same as the app's DealStore.unrounded / clearAgreedTotal().
 */
export function unroundedDeal<D extends { rateIn?: number | null; rateOut?: number | null; agreedCash?: number | null }>(deal: D): D {
  return { ...deal, agreedCash: undefined, rateIn: wholeRate(deal.rateIn), rateOut: wholeRate(deal.rateOut) };
}

/**
 * A line's true share of market at the price it goes at: "80" normally, "99.6" when rounding the
 * total moved it off a whole % (a price that's just the whole % rounded to the cent still reads
 * whole: $6.92 at 80% is $5.54, which is 80.06%). Null without a market. Same as the app's card row.
 */
export function lineShare(unit: number | null, market: number | null | undefined): { label: string; offWhole: boolean } | null {
  if (unit === null || market === null || market === undefined || !(market > 0)) return null;
  const share = (unit / market) * 100;
  const offWhole = Math.abs(unit - round2((market * Math.round(share)) / 100)) > 0.005;
  return { label: offWhole ? share.toFixed(1) : String(Math.round(share)), offWhole };
}

/* ------------------------------ Closed deals ------------------------------ */

/** What a closed deal records, enough to show its card again (the app's DealTotals(record:)). */
export interface DealRecordFigures extends DealRecordTotals {
  inValue: number;
  outValue: number;
  balance: number;
}

/**
 * A closed deal's figures as recorded, for the same card the deal page shows. What came in was
 * worth what it went for plus the value gained; what went out isn't recorded (null).
 */
/** Totals as the deal card shows them: a closed deal doesn't know what went out was worth. */
export type CardTotals = Omit<DealTotals, "inMarket" | "outMarket"> & { inMarket: number | null; outMarket: number | null };

export function recordTotals(r: DealRecordFigures): CardTotals {
  return {
    kind: r.kind,
    inValue: r.inValue,
    outValue: r.outValue,
    balance: r.balance,
    profit: r.profit ?? null,
    equity: r.equity,
    belowCost: 0,
    uncosted: r.uncosted ?? 0,
    ahead: recordAhead(r),
    inMarket: r.inValue > 0 ? round2(r.inValue + r.equity) : null,
    outMarket: null,
  };
}

/** How far ahead, adding up deal by deal (oldest first), from the deals that know it: the climb chart. */
export function profitClimb(records: (DealRecordTotals & { at: string })[]): number[] {
  let running = 0;
  return records
    .filter((r) => recordAhead(r) !== null)
    .sort((a, b) => (a.at < b.at ? -1 : a.at > b.at ? 1 : 0))
    .map((r) => (running = round2(running + (recordAhead(r) ?? 0))));
}

/** The deal that left you furthest ahead (only one that made a profit), or null. */
export function bestDeal<R extends DealRecordTotals>(records: R[]): R | null {
  let best: R | null = null;
  for (const r of records) {
    const a = recordAhead(r) ?? 0;
    if (a > 0 && (best === null || a > (recordAhead(best) ?? 0))) best = r;
  }
  return best;
}
