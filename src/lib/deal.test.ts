import { describe, expect, it } from "vitest";
import { DEFAULT_RATES, aheadTitle, dealDayTotals, dealKind, dealTotals, defaultSideRates, matchesDealSearch, parkedDealName, recordAhead, unitPrice, type DealHistoryRecord } from "./deal";

describe("deal maker", () => {
  it("names the deal from its sides", () => {
    expect(dealKind(2, 0)).toBe("buy");
    expect(dealKind(0, 1)).toBe("sell");
    expect(dealKind(1, 1)).toBe("trade");
    expect(dealKind(0, 0)).toBe("empty");
  });

  it("credits trades higher than outright buys", () => {
    expect(defaultSideRates("buy", DEFAULT_RATES)).toEqual({ in: 0.7, out: 1 });
    expect(defaultSideRates("trade", DEFAULT_RATES)).toEqual({ in: 0.8, out: 1 });
  });

  it("uses a typed price over market × rate", () => {
    expect(unitPrice({ market: 100, qty: 1 }, 0.8)).toBe(80);
    expect(unitPrice({ market: 100, qty: 1, price: 75 }, 0.8)).toBe(75);
    expect(unitPrice({ market: null, qty: 1 }, 0.8)).toBeNull();
  });

  it("lets one line keep its own rate", () => {
    expect(unitPrice({ market: 500, qty: 1, rate: 0.9 }, 0.8)).toBe(450);
    // A typed price still wins over a line rate.
    expect(unitPrice({ market: 500, qty: 1, rate: 0.9, price: 420 }, 0.8)).toBe(420);
    const t = dealTotals([{ market: 500, qty: 1, rate: 0.9 }, { market: 100, qty: 1 }], [], { in: 0.8, out: 1 });
    expect(t.inValue).toBe(530);
  });

  it("balances a trade with cash", () => {
    // Customer brings $200 of market at 80% = $160 credit; takes a $250 card at 100%.
    const t = dealTotals([{ market: 200, qty: 1 }], [{ market: 250, qty: 1, cost: 180 }], { in: 0.8, out: 1 });
    expect(t.kind).toBe("trade");
    expect(t.inValue).toBe(160);
    expect(t.outValue).toBe(250);
    expect(t.balance).toBe(90); // customer pays you
    expect(t.profit).toBe(70);
    expect(t.equity).toBe(40);
    expect(t.belowCost).toBe(0);
  });

  it("flags outgoing lines priced under cost", () => {
    const t = dealTotals([], [{ market: 100, qty: 2, price: 40, cost: 100 }], { in: 0.7, out: 1 });
    expect(t.balance).toBe(80);
    expect(t.profit).toBe(-20);
    expect(t.belowCost).toBe(1);
  });

  it("is a negative balance when you pay out", () => {
    const t = dealTotals([{ market: 50, qty: 3 }], [], { in: 0.7, out: 1 });
    expect(t.balance).toBe(-105);
    expect(t.profit).toBeNull();
  });

  it("adds profit and value gained into how far ahead you come out", () => {
    // In: $1,000 market credited at 80% ($800). Out: a $1,000 card that cost $600.
    const t = dealTotals([{ market: 1000, qty: 1 }], [{ market: 1000, qty: 1, cost: 600 }], { in: 0.8, out: 1 });
    expect(t.profit).toBe(400);
    expect(t.equity).toBe(200);
    expect(t.ahead).toBe(600);
    // Market in − cost out + cash received.
    expect(t.ahead).toBe(1000 - 600 + t.balance);
  });

  it("doesn't depend on how the prices were split", () => {
    const a = dealTotals([{ market: 1000, qty: 1 }], [{ market: 1000, qty: 1, cost: 600 }], { in: 0.8, out: 1 });
    // Same cash, both sides marked up by $150.
    const b = dealTotals([{ market: 1000, qty: 1, price: 950 }], [{ market: 1000, qty: 1, price: 1150, cost: 600 }], { in: 0.8, out: 1 });
    expect(b.balance).toBe(a.balance);
    expect(b.ahead).toBe(a.ahead);
  });

  it("is value gained for a pure buy and profit for a pure sell", () => {
    const buy = dealTotals([{ market: 50, qty: 3 }], [], { in: 0.7, out: 1 });
    expect(buy.ahead).toBe(buy.equity);
    expect(buy.ahead).toBe(45);
    const sell = dealTotals([], [{ market: 100, qty: 2, price: 40, cost: 100 }], { in: 0.7, out: 1 });
    expect(sell.ahead).toBe(sell.profit);
    expect(sell.ahead).toBe(-20);
  });

  it("is unknown while anything going out has no cost", () => {
    const t = dealTotals([{ market: 200, qty: 1 }], [{ market: 250, qty: 1, cost: 180 }, { market: 30, qty: 1 }], { in: 0.8, out: 1 });
    expect(t.uncosted).toBe(1);
    expect(t.ahead).toBeNull();
    expect(dealTotals([], [], { in: 0.7, out: 1 }).ahead).toBeNull();
  });

  it("words the headline for open and closed deals", () => {
    expect(aheadTitle(58)).toBe("You come out ahead");
    expect(aheadTitle(-20, true)).toBe("You came out behind");
    expect(aheadTitle(0, true)).toBe("You broke even");
  });

  it("works out ahead for deals closed before it was recorded", () => {
    expect(recordAhead({ kind: "trade", profit: 971, equity: 730, ahead: 1701, uncosted: 0 })).toBe(1701);
    // Recorded as unknown stays unknown, even with a partial profit.
    expect(recordAhead({ kind: "trade", profit: 70, equity: 40, ahead: null, uncosted: 1 })).toBeNull();
    // Old records: profit + value gained; a buy is all value gained.
    expect(recordAhead({ kind: "trade", profit: 971, equity: 730 })).toBe(1701);
    expect(recordAhead({ kind: "buy", profit: null, equity: 45 })).toBe(45);
    expect(recordAhead({ kind: "sell", profit: -20, equity: 0 })).toBe(-20);
    expect(recordAhead({ kind: "trade", profit: null, equity: 40 })).toBeNull();
  });
});

describe("parked deals and history", () => {
  it("names a parked deal after the time it was parked", () => {
    expect(parkedDealName(new Date(2026, 10, 2, 15, 42))).toBe("Deal at 3:42 PM");
    expect(parkedDealName(new Date(2026, 10, 2, 0, 5))).toBe("Deal at 12:05 AM");
    expect(parkedDealName(new Date(2026, 10, 2, 12, 0))).toBe("Deal at 12:00 PM");
  });

  const rec = (o: Partial<DealHistoryRecord>): DealHistoryRecord => ({ at: "2026-11-02T15:00:00.000Z", kind: "trade", balance: 0, profit: null, equity: 0, ...o });

  it("totals a day's deals: cash both ways, net, ahead and profit", () => {
    const t = dealDayTotals([
      rec({ kind: "sell", balance: 120, profit: 40, ahead: 40, uncosted: 0 }),
      rec({ kind: "buy", balance: -70, equity: 30, ahead: 30, uncosted: 0 }),
      rec({ kind: "trade", balance: 25, profit: 10, equity: 5, ahead: null, uncosted: 1 }),
    ]);
    expect(t).toEqual({ deals: 3, cashIn: 145, cashOut: 70, net: 75, ahead: 70, profit: 50 });
  });

  it("leaves ahead and profit unknown when no deal knows them", () => {
    const t = dealDayTotals([rec({ kind: "trade", balance: 0, ahead: null, uncosted: 2 })]);
    expect(t.ahead).toBeNull();
    expect(t.profit).toBeNull();
    expect(t.net).toBe(0);
  });

  it("searches card names, notes and kind", () => {
    const r = rec({ kind: "sell", notes: "Paid by Venmo", lines: [{ product: { name: "Charizard ex" } }, { product: { name: "Umbreon VMAX" } }] });
    expect(matchesDealSearch(r, "")).toBe(true);
    expect(matchesDealSearch(r, "charizard")).toBe(true);
    expect(matchesDealSearch(r, "venmo")).toBe(true);
    expect(matchesDealSearch(r, "sale umbreon")).toBe(true);
    expect(matchesDealSearch(r, "trade")).toBe(false);
    expect(matchesDealSearch(r, "pikachu")).toBe(false);
  });
});
