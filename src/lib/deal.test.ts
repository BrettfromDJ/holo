import { describe, expect, it } from "vitest";
import { DEFAULT_RATES, agreedDeal, rateForCash, roundStep, roundedCash, withAgreedCash, aheadTitle, dealDayTotals, dealKind, dealTotals, defaultSideRates, matchesDealSearch, parkedDealName, recordAhead, renegotiates, signedAgreedCash, unitPrice, type DealHistoryRecord, type DealLine } from "./deal";

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

describe("agreed cash", () => {
  const settle = (incoming: DealLine[], outgoing: DealLine[], rates: { in: number; out: number }, agreed: number | null) => {
    const a = agreedDeal(incoming, outgoing, rates, agreed);
    return { ...a, totals: dealTotals(a.incoming, a.outgoing, rates) };
  };

  it("leaves the deal alone when nothing is agreed", () => {
    const out = [{ market: 100, qty: 1 }];
    const a = agreedDeal([], out, { in: 0.7, out: 1 }, null);
    expect(a.outgoing).toBe(out);
    expect(a.side).toBeNull();
    expect(agreedDeal([], [], { in: 0.7, out: 1 }, 50).side).toBeNull();
  });

  it("spreads a sale's agreed cash across what goes out, by each line's total", () => {
    const s = settle([], [{ market: 100, qty: 1 }, { market: 50, qty: 1 }], { in: 0.7, out: 1 }, 120);
    expect(s.side).toBe("out");
    expect(s.outgoing.map((l) => l.price)).toEqual([80, 40]);
    expect(s.totals.balance).toBe(120);
    expect(s.share).toBeCloseTo(0.8);
  });

  it("moves what comes in the other way on a buy, exact to the cent", () => {
    // $100 and $30 market at 70%: $91 coming in. Agreed: you pay $100.
    const s = settle([{ market: 100, qty: 1 }, { market: 30, qty: 1 }], [], { in: 0.7, out: 1 }, -100);
    expect(s.side).toBe("in");
    expect(s.incoming.map((l) => l.price)).toEqual([76.93, 23.07]);
    expect(s.totals.balance).toBe(-100);
    expect(s.totals.inValue).toBe(100);
  });

  it("puts the leftover cent on the biggest line", () => {
    const s = settle([], [{ market: 10, qty: 1 }, { market: 10, qty: 1 }, { market: 10, qty: 1 }], { in: 0.7, out: 1 }, 25);
    expect(s.outgoing.map((l) => l.price)).toEqual([8.34, 8.33, 8.33]);
    expect(s.totals.balance).toBe(25);
  });

  it("works per unit for several copies", () => {
    const s = settle([], [{ market: 10, qty: 3 }], { in: 0.7, out: 1 }, 25);
    expect(s.outgoing[0].price! * 3).toBeCloseTo(25, 10);
    expect(s.totals.balance).toBe(25);
  });

  it("never takes a line below $0, getting as close as it can", () => {
    const s = settle([{ market: 100, qty: 1 }], [{ market: 50, qty: 1 }], { in: 0.8, out: 1 }, -120);
    // Going out can only drop to $0: you pay $80, not $120.
    expect(s.outgoing[0].price).toBe(0);
    expect(s.totals.balance).toBe(-80);
  });

  it("changes ahead by exactly the cash moved", () => {
    const rates = { in: 0.8, out: 1 };
    const base = dealTotals([{ market: 100, qty: 1 }], [{ market: 100, qty: 1, cost: 60 }], rates);
    const s = settle([{ market: 100, qty: 1 }], [{ market: 100, qty: 1, cost: 60 }], rates, 0);
    expect(base.balance).toBe(20);
    expect(s.totals.balance).toBe(0);
    expect(s.totals.profit).toBe(20);
    expect(s.totals.ahead).toBe(base.ahead! - 20);
    expect(s.totals.ahead).toBe(100 - 60 + 0);
  });

  it("leaves lines with no price as they are", () => {
    const s = settle([], [{ market: null, qty: 1 }, { market: 40, qty: 1 }], { in: 0.7, out: 1 }, 30);
    expect(s.outgoing[0].price).toBeUndefined();
    expect(s.outgoing[1].price).toBe(30);
    expect(s.share).toBeCloseTo(0.75);
  });

  it("keeps who pays whom when you type an amount", () => {
    expect(signedAgreedCash(50, { balance: 42, inValue: 0, outValue: 42 })).toBe(50);
    expect(signedAgreedCash(50, { balance: -42, inValue: 42, outValue: 0 })).toBe(-50);
    expect(signedAgreedCash(50, { balance: 0, inValue: 10, outValue: 10 })).toBe(-50);
    expect(signedAgreedCash(50, { balance: 0, inValue: 0, outValue: 10 })).toBe(50);
  });

  it("knows a renegotiation from other edits", () => {
    const base = { in: [{ key: "a", qty: 1, price: null, rate: null }], out: [], rateIn: null, rateOut: null };
    expect(renegotiates(base, { ...base, rateIn: 0.75 })).toBe(true);
    expect(renegotiates(base, { ...base, in: [{ key: "a", qty: 2, price: null, rate: null }] })).toBe(true);
    expect(renegotiates(base, { ...base, in: [{ key: "a", qty: 1, price: 12, rate: null }] })).toBe(true);
    expect(renegotiates(base, { ...base, in: [{ key: "a", qty: 1, price: null, rate: 0.9 }] })).toBe(true);
    expect(renegotiates(base, { ...base, in: [] })).toBe(true);
    expect(renegotiates(base, { ...base, out: [{ key: "b", qty: 1 }] })).toBe(true);
    // Notes, photos, tracking and undefined-vs-null don't count.
    expect(renegotiates(base, { ...base, in: [{ key: "a", qty: 1 }], rateIn: undefined })).toBe(false);
  });
});

describe("round up", () => {
  it("rounds the cash up to the next step, keeping who pays whom", () => {
    expect(roundedCash(1151.2, 5)).toBe(1155);
    expect(roundedCash(-1151.2, 5)).toBe(-1155);
    expect(roundedCash(1151.2, 1)).toBe(1152);
    expect(roundedCash(1151.2, 10)).toBe(1160);
    expect(roundedCash(1151.2, 25)).toBe(1175);
    expect(roundedCash(1151.2, 50)).toBe(1200);
    expect(roundedCash(1151.2, 100)).toBe(1200);
    expect(roundedCash(1151.01)).toBe(1155);
    expect(roundedCash(0.5, 5)).toBe(5);
  });

  it("has nothing to do on a multiple or with no cash", () => {
    expect(roundedCash(1155, 5)).toBeNull();
    expect(roundedCash(-1200, 100)).toBeNull();
    expect(roundedCash(42, 1)).toBeNull();
    expect(roundedCash(0, 5)).toBeNull();
  });

  it("reads the step from the settings, $5 unless it's one of the steps", () => {
    expect(roundStep({})).toBe(5);
    expect(roundStep({ roundStep: null })).toBe(5);
    expect(roundStep({ roundStep: 25 })).toBe(25);
    expect(roundStep({ roundStep: 7 })).toBe(5);
  });
});

describe("cash moves the slider", () => {
  type Priced = { in: DealLine[]; out: DealLine[]; rateIn?: number | null; rateOut?: number | null; agreedCash?: number | null };
  const settled = (d: Priced, defaults: { in: number; out: number }) => {
    const rates = { in: d.rateIn ?? defaults.in, out: d.rateOut ?? defaults.out };
    const a = agreedDeal(d.in, d.out, rates, d.agreedCash);
    return dealTotals(a.incoming, a.outgoing, rates);
  };

  it("solves a sale's rate exactly", () => {
    // $1,000 market going out at 100%: the customer pays $900 → 90%.
    expect(rateForCash([], [{ market: 1000, qty: 1 }], { in: 0.7, out: 1 }, 900)).toEqual({ side: "out", rate: 0.9 });
  });

  it("solves a buy's rate (you pay, so the cash is negative)", () => {
    // $200 coming in; you pay $150 → 75%.
    expect(rateForCash([{ market: 200, qty: 1 }], [], { in: 0.7, out: 1 }, -150)).toEqual({ side: "in", rate: 0.75 });
  });

  it("moves what goes out in a trade, around fixed prices and lines with their own %", () => {
    // In: $500 at 80% = $400. Out: a $100 typed price, a line at its own 50% of $100, and $1,000
    // that follows the side's %. Customer pays $700: 100 + 50 + 1000r − 400 = 700 → r = 0.95.
    const incoming = [{ market: 500, qty: 1 }];
    const outgoing = [{ market: 300, qty: 1, price: 100 }, { market: 100, qty: 1, rate: 0.5 }, { market: 500, qty: 2 }];
    const r = rateForCash(incoming, outgoing, { in: 0.8, out: 1 }, 700);
    expect(r?.side).toBe("out");
    expect(r?.rate).toBeCloseTo(0.95, 6);
    expect(dealTotals(incoming, outgoing, { in: 0.8, out: r!.rate }).balance).toBeCloseTo(700, 2);
  });

  it("stops at the slider's range", () => {
    expect(rateForCash([], [{ market: 100, qty: 1 }], { in: 0.7, out: 1 }, 10)?.rate).toBe(0.4);
    expect(rateForCash([], [{ market: 100, qty: 1 }], { in: 0.7, out: 1 }, 500)?.rate).toBe(1.2);
  });

  it("has nothing to move when every line is fixed, or the deal is empty", () => {
    expect(rateForCash([], [{ market: 100, qty: 1, price: 90 }], { in: 0.7, out: 1 }, 80)).toBeNull();
    expect(rateForCash([], [], { in: 0.7, out: 1 }, 80)).toBeNull();
  });

  it("sets the rate and the agreed cash together, landing to the cent", () => {
    const d: Priced = { in: [], out: [{ market: 1279.11, qty: 1 }], rateIn: null, rateOut: null };
    const next = withAgreedCash(d, { in: 0.7, out: 1 }, 1155);
    expect(next.agreedCash).toBe(1155);
    expect(next.rateOut).toBeCloseTo(1155 / 1279.11, 6);
    expect(settled(next, { in: 0.7, out: 1 }).balance).toBe(1155);
    // Not a renegotiation the deal should undo: the slider and the agreed cash moved together.
  });

  it("covers what the range can't with the agreed cash", () => {
    const d: Priced = { in: [], out: [{ market: 100, qty: 1 }], rateIn: null, rateOut: null };
    const next = withAgreedCash(d, { in: 0.7, out: 1 }, 20);
    expect(next.rateOut).toBe(0.4);
    expect(next.agreedCash).toBe(20);
    expect(settled(next, { in: 0.7, out: 1 }).balance).toBe(20);
  });

  it("only sets the agreed cash when nothing follows the side's %", () => {
    const d: Priced = { in: [], out: [{ market: 100, qty: 1, price: 90 }], rateIn: null, rateOut: null };
    const next = withAgreedCash(d, { in: 0.7, out: 1 }, 80);
    expect(next.rateOut).toBeNull();
    expect(settled(next, { in: 0.7, out: 1 }).balance).toBe(80);
  });
});
