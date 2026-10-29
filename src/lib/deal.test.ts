import { describe, expect, it } from "vitest";
import { DEFAULT_RATES, dealKind, dealTotals, defaultSideRates, unitPrice } from "./deal";

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
});
