import { describe, expect, it } from "vitest";
import { priceKey } from "../../types";
import { buildLedger, costBasisOf, effectiveTransactions, quantityOf, realizedOf } from "../ledger";
import { computeHoldings, computeTimeline, monthlyActivity, performanceOf, summarize, totalRealized } from "../portfolio";
import { PriceResolver } from "../prices";
import { data, price, series, tx } from "./fixtures";

const TODAY = "2026-03-10";

describe("FIFO ledger", () => {
  it("loads fees, shipping and tax into the cost basis", () => {
    const l = buildLedger([tx({ type: "purchase", date: "2026-01-01", quantity: 2, unitPrice: 100, fees: 5, shipping: 10, tax: 15 })]);
    const pos = [...l.positions.values()][0];
    expect(quantityOf(pos)).toBe(2);
    expect(costBasisOf(pos)).toBe(230);
    expect(pos.lots[0].unitCost).toBe(115);
  });

  it("keeps separate lots and consumes them first-in first-out on partial sales", () => {
    const l = buildLedger([
      tx({ type: "purchase", date: "2026-01-01", quantity: 2, unitPrice: 100 }),
      tx({ type: "purchase", date: "2026-02-01", quantity: 3, unitPrice: 150 }),
      tx({ type: "sale", date: "2026-03-01", quantity: 3, unitPrice: 200, fees: 30 }),
    ]);
    const pos = [...l.positions.values()][0];
    expect(quantityOf(pos)).toBe(2);
    // Remaining units both come from the second lot.
    expect(costBasisOf(pos)).toBe(300);
    // Sold 2 @100 + 1 @150 = 350 cost; proceeds 600 - 30 = 570.
    expect(pos.realized[0].costBasis).toBe(350);
    expect(pos.realized[0].proceeds).toBe(570);
    expect(realizedOf(pos)).toBe(220);
  });

  it("supports lot-cost entry spread evenly across units", () => {
    const l = buildLedger([tx({ type: "purchase", date: "2026-01-01", quantity: 3, unitPrice: 1000 / 3 })]);
    const pos = [...l.positions.values()][0];
    expect(costBasisOf(pos)).toBeCloseTo(1000, 8);
  });

  it("warns and clamps when selling more than is held", () => {
    const l = buildLedger([
      tx({ type: "purchase", date: "2026-01-01", quantity: 1, unitPrice: 100 }),
      tx({ type: "sale", date: "2026-01-02", quantity: 2, unitPrice: 120 }),
    ]);
    const pos = [...l.positions.values()][0];
    expect(quantityOf(pos)).toBe(0);
    expect(pos.realized[0].quantity).toBe(1);
    expect(pos.realized[0].proceeds).toBe(120);
    expect(l.warnings).toHaveLength(1);
  });

  it("applies corrections without mutating the audit trail, and voids with quantity 0", () => {
    const original = tx({ id: "a", type: "purchase", date: "2026-01-01", quantity: 2, unitPrice: 100 });
    const voided = tx({ id: "b", type: "purchase", date: "2026-01-02", quantity: 5, unitPrice: 10 });
    const fix = tx({ id: "c", type: "correction", correctsId: "a", date: "2026-01-01", quantity: 2, unitPrice: 90 });
    const fix2 = tx({ id: "d", type: "correction", correctsId: "c", date: "2026-01-01", quantity: 2, unitPrice: 80 });
    const kill = tx({ id: "e", type: "correction", correctsId: "b", date: "2026-01-02", quantity: 0, unitPrice: 0 });
    const eff = effectiveTransactions([original, voided, fix, fix2, kill]);
    expect(eff.map((t) => t.id)).toEqual(["a"]);
    expect(eff[0].unitPrice).toBe(80);
    expect(original.unitPrice).toBe(100);
  });

  it("treats negative adjustments as disposals with zero proceeds", () => {
    const l = buildLedger([
      tx({ type: "purchase", date: "2026-01-01", quantity: 2, unitPrice: 100 }),
      tx({ type: "adjustment", date: "2026-01-05", quantity: -1, unitPrice: 0 }),
    ]);
    const pos = [...l.positions.values()][0];
    expect(quantityOf(pos)).toBe(1);
    expect(realizedOf(pos)).toBe(-100);
  });
});

describe("holdings and summary", () => {
  it("adding inventory at market price never creates investment gain", () => {
    // $5,000 collection, then buy a $1,000 box worth $1,000.
    const d = data({
      transactions: [
        tx({ productId: "p:a", type: "purchase", date: "2026-01-01", quantity: 1, unitPrice: 3000 }),
        tx({ productId: "p:box", type: "purchase", date: TODAY, quantity: 1, unitPrice: 1000 }),
      ],
      prices: { [priceKey("p:a", null)]: price("p:a", 5000), [priceKey("p:box", null)]: price("p:box", 1000) },
      history: { ...series("p:a", [["2026-03-09", 5000]]), ...series("p:box", [["2026-03-09", 1000]]) },
    });
    const holdings = computeHoldings(d, TODAY);
    const s = summarize(holdings, 0);
    expect(s.marketValue).toBe(6000);
    expect(s.costBasis).toBe(4000);
    expect(s.unrealized).toBe(2000); // unchanged from before the purchase
    expect(s.dayChange).toBe(0);

    const tl = computeTimeline(d, TODAY);
    const last = tl[tl.length - 1];
    expect(last.value).toBe(6000);
    expect(last.marketGain).toBe(0);
    expect(last.dailyReturn).toBe(0);
    expect(last.invested).toBe(1000);
  });

  it("never treats a missing market price as $0", () => {
    const d = data({
      transactions: [
        tx({ productId: "p:a", type: "purchase", date: "2026-01-01", quantity: 1, unitPrice: 100 }),
        tx({ productId: "p:b", type: "purchase", date: "2026-01-01", quantity: 1, unitPrice: 50 }),
      ],
      prices: { [priceKey("p:a", null)]: price("p:a", 150), [priceKey("p:b", null)]: price("p:b", null) },
    });
    const holdings = computeHoldings(d, TODAY);
    const b = holdings.find((h) => h.identity.productId === "p:b")!;
    expect(b.price).toBeNull();
    expect(b.value).toBeNull();
    expect(b.unrealized).toBeNull();
    expect(b.priceStatus).toBe("unavailable");
    const s = summarize(holdings, 0);
    expect(s.marketValue).toBe(150);
    expect(s.costBasis).toBe(150); // total invested still includes the unpriced item
    expect(s.unrealized).toBe(50); // compared against priced cost basis only
    expect(s.unpricedCount).toBe(1);
  });

  it("measures daily change only on units held at the previous close", () => {
    const d = data({
      transactions: [
        tx({ type: "purchase", date: "2026-01-01", quantity: 2, unitPrice: 100 }),
        tx({ type: "purchase", date: TODAY, quantity: 1, unitPrice: 110 }),
      ],
      prices: { [priceKey("p:box", null)]: price("p:box", 110) },
      history: series("p:box", [["2026-03-09", 100]]),
    });
    const [h] = computeHoldings(d, TODAY);
    expect(h.quantity).toBe(3);
    expect(h.dayChange).toBe(20); // 2 units × $10, the new unit adds nothing
    expect(h.dayChangePct).toBeCloseTo(0.1);
    const s = summarize([h], 0);
    expect(s.dayChangePct).toBeCloseTo(0.1);
  });

  it("recovers yesterday's price from the source's 24h change when no snapshot exists", () => {
    const d = data({ prices: { [priceKey("p:box", null)]: price("p:box", 110, { change24hPct: 10 }) } });
    const r = new PriceResolver(d, TODAY).resolve({ productId: "p:box", printing: null, condition: "Sealed", grade: null }, "2026-03-09");
    expect(r?.origin).toBe("derived-24h");
    expect(r?.price).toBeCloseTo(100);
  });

  it("does not carry a stale snapshot forward indefinitely", () => {
    const d = data({ history: series("p:box", [["2026-01-01", 100]]) });
    const r = new PriceResolver(d, TODAY).resolve({ productId: "p:box", printing: null, condition: "Sealed", grade: null }, "2026-02-01");
    expect(r).toBeNull();
  });

  it("values graded holdings from manual valuations only", () => {
    const identity = { productId: "p:card", printing: "Holofoil", condition: "Near Mint" as const, grade: { company: "PSA", grade: "10" } };
    const d = data({
      transactions: [tx({ ...identity, type: "purchase", date: "2026-01-01", quantity: 1, unitPrice: 500 })],
      prices: { [priceKey("p:card", "Holofoil")]: price("p:card", 40, { printing: "Holofoil" }) },
      manualValues: { "p:card|Holofoil|Near Mint|PSA 10": { value: 900, date: "2026-02-01" } },
    });
    const [h] = computeHoldings(d, TODAY);
    expect(h.category).toBe("graded");
    expect(h.price).toBe(900);
    expect(h.priceStatus).toBe("manual");
  });
});

describe("time-weighted performance", () => {
  it("chains daily returns so contributions don't distort percentage performance", () => {
    // Day 1: buy 1 @100. Day 2: price 110 (+10%). Day 3: buy 9 more @110, price 110.
    // Day 4: price 121 (+10%). TWR = 1.1 × 1.1 − 1 = 21%, regardless of the big buy.
    const d = data({
      transactions: [
        tx({ type: "purchase", date: "2026-03-01", quantity: 1, unitPrice: 100 }),
        tx({ type: "purchase", date: "2026-03-03", quantity: 9, unitPrice: 110 }),
      ],
      history: series("p:box", [
        ["2026-03-01", 100],
        ["2026-03-02", 110],
        ["2026-03-03", 110],
        ["2026-03-04", 121],
      ]),
    });
    const tl = computeTimeline(d, "2026-03-04");
    expect(tl.map((p) => p.marketGain)).toEqual([0, 10, 0, 110]);
    const perf = performanceOf(tl)!;
    expect(perf.marketGain).toBe(120);
    expect(perf.twr).toBeCloseTo(0.21, 10);
    // A naive balance comparison would claim (1210 − 100) / 100 = 1110%.
    expect(perf.endValue).toBe(1210);
  });

  it("handles sales: sold units stop contributing after the sale day", () => {
    const d = data({
      transactions: [
        tx({ type: "purchase", date: "2026-03-01", quantity: 2, unitPrice: 100 }),
        tx({ type: "sale", date: "2026-03-02", quantity: 1, unitPrice: 120 }),
      ],
      history: series("p:box", [
        ["2026-03-01", 100],
        ["2026-03-02", 120],
        ["2026-03-03", 60],
      ]),
    });
    const tl = computeTimeline(d, "2026-03-03");
    // Day 2: both units held at prior close gained $20 each. Day 3: one unit lost $60.
    expect(tl.map((p) => p.marketGain)).toEqual([0, 40, -60]);
    expect(tl[1].proceeds).toBe(120);
    expect(tl[2].value).toBe(60);
    expect(performanceOf(tl)!.twr).toBeCloseTo(1.2 * 0.5 - 1, 10);
    expect(totalRealized(d, "2026-03-03").total).toBe(20);
  });

  it("excludes holdings whose price is missing on either day", () => {
    const d = data({
      transactions: [
        tx({ productId: "p:a", type: "purchase", date: "2026-03-01", quantity: 1, unitPrice: 100 }),
        tx({ productId: "p:b", type: "purchase", date: "2026-03-01", quantity: 1, unitPrice: 100 }),
      ],
      history: {
        ...series("p:a", [["2026-03-01", 100], ["2026-03-02", 110]]),
        // p:b only gets its first price on day 2 — that must not count as gain.
        ...series("p:b", [["2026-03-02", 500]]),
      },
    });
    const tl = computeTimeline(d, "2026-03-02");
    expect(tl[0].unpricedHoldings).toBe(1);
    expect(tl[1].marketGain).toBe(10);
    expect(tl[1].dailyReturn).toBeCloseTo(0.1);
  });

  it("groups invested capital by month", () => {
    const d = data({
      transactions: [
        tx({ type: "purchase", date: "2026-01-15", quantity: 1, unitPrice: 100, shipping: 5 }),
        tx({ type: "sale", date: "2026-03-02", quantity: 1, unitPrice: 150, fees: 10 }),
      ],
    });
    expect(monthlyActivity(d, TODAY)).toEqual([
      { month: "2026-01", invested: 105, proceeds: 0 },
      { month: "2026-02", invested: 0, proceeds: 0 },
      { month: "2026-03", invested: 0, proceeds: 140 },
    ]);
  });
});
