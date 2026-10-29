import { describe, expect, it } from "vitest";
import { PriceResolver } from "./finance/prices";
import { gradedLadder, gradedPriceKey, gradingOutlook, isStaleValue, liquidityLabel, liquidityOf, sampleMultiple, sampleSalesPerYear, withEbayGradedPrices, withSampleGradedPrices, ebayGradedTargets } from "./graded";
import { priceKey, type CollectionData, type NormalizedPrice, type Transaction } from "./types";

const today = "2026-10-28";
const raw: NormalizedPrice = { productId: "p1", printing: null, market: 100, low: null, change24hPct: null, change7dPct: null, change30dPct: null, updatedAt: null, fetchedAt: null, source: "tcgapi", status: "live" };
const slab: Transaction = { id: "t1", type: "purchase", date: "2026-01-01", productId: "p1", printing: null, condition: "Near Mint", grade: { company: "PSA", grade: "10" }, quantity: 1, unitPrice: 300, fees: 0, shipping: 0, tax: 0, createdAt: "" };

function data(over: Partial<CollectionData> = {}): CollectionData {
  return {
    products: {},
    transactions: [slab],
    watchlist: [],
    prices: { [priceKey("p1", null)]: raw },
    history: { [priceKey("p1", null)]: [{ date: "2026-10-01", price: 90 }] },
    manualValues: {},
    preferences: { currency: "USD", defaultView: "grid", chartRange: "1M" },
    ...over,
  };
}

describe("graded prices", () => {
  it("ranks higher grades above lower ones and stays stable per product", () => {
    const ten = sampleMultiple("p1", { company: "PSA", grade: "10" });
    const nine = sampleMultiple("p1", { company: "PSA", grade: "9" });
    expect(ten).toBeGreaterThan(nine);
    expect(sampleMultiple("p1", { company: "PSA", grade: "10" })).toBe(ten);
  });

  // Demo products get sample graded prices; real ones are priced from eBay.
  const demoSlab: Transaction = { ...slab, productId: "sample:p1" };
  const demo = () => data({ transactions: [demoSlab], prices: { [priceKey("sample:p1", null)]: { ...raw, productId: "sample:p1" } }, history: { [priceKey("sample:p1", null)]: [{ date: "2026-10-01", price: 90 }] } });

  it("adds a sample price and history under the graded key for demo products", () => {
    const out = withSampleGradedPrices(demo(), today);
    const key = gradedPriceKey("sample:p1", null, slab.grade!);
    expect(out.prices[key].market).toBeGreaterThan(100);
    expect(out.history[key].at(-1)?.date).toBe(today);
    expect(out.history[key]).toHaveLength(2);
    // Real products aren't given made-up slab prices.
    expect(withSampleGradedPrices(data(), today).prices[gradedPriceKey("p1", null, slab.grade!)]).toBeUndefined();
  });

  it("values a slab from the graded price, and a manual value overrides it", () => {
    const priced = withSampleGradedPrices(demo(), today);
    const auto = new PriceResolver(priced, today).resolve(demoSlab, today);
    expect(auto?.origin).toBe("current");
    const manual = new PriceResolver({ ...priced, manualValues: { "sample:p1||Near Mint|PSA 10": { value: 777, date: "2026-10-20" } } }, today).resolve(demoSlab, today);
    expect(manual).toMatchObject({ price: 777, origin: "manual" });
  });

  it("prices real slabs from eBay sales for their grade, following the raw trend", () => {
    const ebay = { [priceKey("p1", null)]: { printing: null, ungraded: { median: 100, count: 9, lastPrice: 100, lastSold: null }, graded: { "PSA 10": { median: 500, count: 4, lastPrice: 520, lastSold: "2026-10-27" } }, sales: [], asOf: today, days: 30 } };
    expect(ebayGradedTargets(data())).toEqual([{ productId: "p1", printing: null }]);
    const out = withEbayGradedPrices(data(), ebay, today);
    const key = gradedPriceKey("p1", null, slab.grade!);
    expect(out.prices[key]).toMatchObject({ market: 500, source: "tcgapi" });
    // Raw was 90 on Oct 1 against 100 now; the slab history scales by 500 / 100.
    expect(out.history[key]).toEqual([{ date: "2026-10-01", price: 450 }, { date: today, price: 500 }]);
    // A grade that hasn't sold stays unpriced.
    const psa9: Transaction = { ...slab, id: "t2", grade: { company: "PSA", grade: "9" } };
    expect(withEbayGradedPrices(data({ transactions: [psa9] }), ebay, today).prices[gradedPriceKey("p1", null, psa9.grade!)]).toBeUndefined();
  });

  it("has no ladder without a raw price", () => {
    expect(gradedLadder("p1", null)).toEqual([]);
    expect(gradedLadder("p1", 100).length).toBeGreaterThan(3);
  });

  it("uses eBay PSA 10 and 9 sales when the card has them", () => {
    const o = gradingOutlook("tcgapi:1", 100, { fee: 25, shipping: 10 }, { psa10: 640, psa9: 210, psa10Count: 3 });
    expect(o).toMatchObject({ psa10: 640, psa9: 210, psa10Sales: 36, source: "sales", upside10: 505 });
    // A PSA 9 that hasn't sold falls back to the curve, and the outlook says it's an estimate.
    expect(gradingOutlook("tcgapi:1", 100, { fee: 25, shipping: 10 }, { psa10: 640, psa9: null, psa10Count: 3 }).source).toBe("estimate");
    expect(gradingOutlook("sample:p1", 100, { fee: 25, shipping: 10 }).source).toBe("sample");
  });

  it("weighs grading costs", () => {
    const o = gradingOutlook("p1", 100, { fee: 25, shipping: 10 });
    expect(o.upside10).toBeCloseTo(o.psa10 - 135);
  });

  it("flags old manual values", () => {
    expect(isStaleValue("2026-07-01", today)).toBe(true);
    expect(isStaleValue("2026-10-01", today)).toBe(false);
    expect(isStaleValue(null, today)).toBe(false);
  });

  it("sells raw copies more often than PSA 10s", () => {
    const raw = sampleSalesPerYear("p1", null, 100);
    const ten = sampleSalesPerYear("p1", { company: "PSA", grade: "10" }, 100);
    expect(raw).toBeGreaterThan(ten);
  });

  it("describes how easy something is to sell", () => {
    expect(liquidityOf(104)).toBe("often");
    expect(liquidityLabel(104)).toBe("Easy to sell");
    expect(liquidityOf(24)).toBe("regular");
    expect(liquidityLabel(5)).toBe("Hard to sell");
  });
});
