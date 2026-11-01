import { describe, expect, it } from "vitest";
import type { EbaySale, EbaySales } from "./ebay-types";
import { PriceResolver } from "./finance/prices";
import { gradedPriceKey, holdingPriceKey, sampleMultiple, withEbayGradedPrices, withSampleGradedPrices } from "./graded";
import { sellSpeed } from "./liquidity";
import { CGC_GEM_MINT_10, CGC_PRISTINE_10, cgcTenValue, gradedSales, gradedStats, isCgcTenGrade, isPristineTitle, pristinePremium, slabLabel } from "./pristine";
import { holdingKey, priceKey, type CollectionData, type NormalizedPrice, type Transaction } from "./types";
import { gradedLookup, gradedPrice } from "./worth";

// Same inputs and expected outputs as the app's PristineTests.swift.
const AS_OF = "2026-10-30";
const TODAY = "2026-11-01";

const sale = (price: number, soldDate: string, title: string, grade: string | null = "CGC 10"): EbaySale => ({ soldDate, price, bestOffer: false, listPrice: null, grade, condition: null, title, url: "" });

/** Five CGC 10s this month (two say pristine), an older Pristine, and a PSA 10 whose title happens to say pristine. */
const ebay = (sales?: EbaySale[]): EbaySales => ({
  printing: null,
  ungraded: { median: 100, count: 8, lastPrice: 100, lastSold: AS_OF },
  graded: {
    "CGC 10": { median: 1000, count: 5, lastPrice: 1500, lastSold: "2026-10-28" },
    "PSA 10": { median: 2000, count: 1, lastPrice: 2000, lastSold: "2026-10-26" },
  },
  sales: sales ?? [
    sale(1500, "2026-10-28", "Charizard CGC Pristine 10"),
    sale(2000, "2026-10-26", "Charizard PSA 10 pristine condition", "PSA 10"),
    sale(900, "2026-10-25", "Charizard CGC 10 Gem Mint"),
    sale(1700, "2026-10-20", "CHARIZARD cgc PRISTINE 10 gold label"),
    sale(1000, "2026-10-18", "Charizard CGC 10"),
    sale(950, "2026-10-10", "CGC Gem Mint 10 Charizard"),
    sale(1400, "2026-09-15", "Charizard CGC pristine 10"),
  ],
  asOf: AS_OF,
  days: 30,
});

const cgc10 = { company: "CGC", grade: "10" };

describe("CGC Pristine 10 and Gem Mint 10", () => {
  it("tells them apart by the title, any case", () => {
    expect(pristinePremium).toBe(1.6);
    expect(isPristineTitle("Charizard CGC Pristine 10")).toBe(true);
    expect(isPristineTitle("CHARIZARD cgc PRISTINE 10")).toBe(true);
    expect(isPristineTitle("Charizard CGC 10 Gem Mint")).toBe(false);
    expect(isCgcTenGrade("cgc", "10")).toBe(true);
    expect(isCgcTenGrade("CGC", "9.5")).toBe(false);
    expect(isCgcTenGrade("PSA", "10")).toBe(false);
    expect(slabLabel(cgc10, true)).toBe(CGC_PRISTINE_10);
    expect(slabLabel(cgc10, false)).toBe(CGC_GEM_MINT_10);
    expect(slabLabel({ company: "PSA", grade: "10" }, true)).toBe("PSA 10");
  });

  it("splits CGC 10 sales into Pristine and Gem Mint figures", () => {
    // Pristine: 1500 and 1700 this month; the September one only counts as the latest when nothing newer.
    expect(gradedStats(ebay(), CGC_PRISTINE_10)).toEqual({ median: 1600, count: 2, lastPrice: 1500, lastSold: "2026-10-28" });
    expect(gradedStats(ebay(), CGC_GEM_MINT_10)).toEqual({ median: 950, count: 3, lastPrice: 900, lastSold: "2026-10-25" });
    // Other labels are eBay's own figures; "CGC 10" still has every CGC 10.
    expect(gradedStats(ebay(), "CGC 10")).toEqual({ median: 1000, count: 5, lastPrice: 1500, lastSold: "2026-10-28" });
    expect(gradedStats(ebay(), "PSA 10")?.median).toBe(2000);
    expect(gradedSales(ebay(), CGC_PRISTINE_10).map((s) => s.price)).toEqual([1500, 1700, 1400]);
    expect(gradedSales(ebay(), CGC_GEM_MINT_10).map((s) => s.price)).toEqual([900, 1000, 950]);
  });

  it("keeps eBay's CGC 10 figures for Gem Mint when no listing says pristine", () => {
    const e = ebay([sale(900, "2026-10-25", "Charizard CGC 10"), sale(1000, "2026-10-18", "Charizard CGC 10 Gem Mint")]);
    expect(gradedStats(e, CGC_GEM_MINT_10)).toEqual({ median: 1000, count: 5, lastPrice: 1500, lastSold: "2026-10-28" });
    expect(gradedStats(e, CGC_PRISTINE_10)).toBeNull();
    // Only an old Pristine sale: none this month, but it's still the latest.
    const old = ebay([sale(900, "2026-10-25", "Charizard CGC 10"), sale(1400, "2026-09-15", "Charizard CGC pristine 10")]);
    expect(gradedStats(old, CGC_PRISTINE_10)).toEqual({ median: null, count: 0, lastPrice: 1400, lastSold: "2026-09-15" });
    expect(gradedStats(old, CGC_GEM_MINT_10)).toEqual({ median: 900, count: 1, lastPrice: 900, lastSold: "2026-10-25" });
  });

  it("values a CGC 10 slab: its own sales, else Gem Mint × the premium for a Pristine", () => {
    const gem = gradedStats(ebay(), CGC_GEM_MINT_10);
    const pri = gradedStats(ebay(), CGC_PRISTINE_10);
    expect(cgcTenValue(gem, pri, 800, false)).toMatchObject({ value: 950, basis: "sales" });
    expect(cgcTenValue(gem, pri, 800, true)).toMatchObject({ value: 1600, basis: "sales" });
    // One Pristine sale isn't enough: the Gem Mint value × 1.6.
    const onePri = { median: 1500, count: 1, lastPrice: 1500, lastSold: "2026-10-28" };
    expect(cgcTenValue(gem, onePri, 800, true)).toMatchObject({ value: 1520, basis: "premium" });
    // Gem Mint with one sale: PriceCharting's CGC 10 (a Gem Mint), and the Pristine from it.
    const oneGem = { median: 900, count: 1, lastPrice: 900, lastSold: "2026-10-25" };
    expect(cgcTenValue(oneGem, onePri, 800, false)).toMatchObject({ value: 800, basis: "other" });
    expect(cgcTenValue(oneGem, onePri, 800, true)).toMatchObject({ value: 1280, basis: "premium" });
    // No guide: the Gem Mint's own median.
    expect(cgcTenValue(oneGem, null, null, false)).toMatchObject({ value: 900, basis: "other" });
    expect(cgcTenValue(oneGem, null, null, true)).toMatchObject({ value: 1440, basis: "premium" });
    // Nothing for Gem Mint: a Pristine's last sale, else nothing.
    expect(cgcTenValue(null, { median: null, count: 0, lastPrice: 1400, lastSold: "2026-09-15" }, null, true)).toMatchObject({ value: 1400, basis: "other" });
    expect(cgcTenValue(null, null, null, true)).toBeNull();
    expect(cgcTenValue(null, null, null, false)).toBeNull();
  });

  it("prices the Graded prices rows and the lookup", () => {
    const pc = { ungraded: 100, grades: { "CGC 10": 800 }, updatedAt: "2026-10-30" };
    expect(gradedPrice("p", cgc10, pc, ebay(), 100)).toEqual({ value: 950, source: { kind: "ebay", count: 3 } });
    expect(gradedPrice("p", cgc10, pc, ebay(), 100, true)).toEqual({ value: 1600, source: { kind: "ebay", count: 2 } });
    // One Pristine sale: Gem Mint × 1.6, an estimate.
    const one = ebay([sale(1500, "2026-10-28", "Charizard CGC Pristine 10"), sale(900, "2026-10-25", "CGC 10"), sale(1000, "2026-10-18", "CGC 10")]);
    expect(gradedPrice("p", cgc10, pc, one, 100)).toEqual({ value: 950, source: { kind: "ebay", count: 2 } });
    expect(gradedPrice("p", cgc10, pc, one, 100, true)).toEqual({ value: 1520, source: { kind: "premium" } });
    // No sales: PriceCharting's CGC 10 is the Gem Mint 10.
    expect(gradedPrice("p", cgc10, pc, null, 100)).toEqual({ value: 800, source: { kind: "guide" } });
    expect(gradedPrice("p", cgc10, pc, null, 100, true)).toEqual({ value: 1280, source: { kind: "premium" } });
    // Nothing but the curve.
    const curve = Math.round(100 * sampleMultiple("p", cgc10) * 100) / 100;
    expect(gradedPrice("p", cgc10, null, null, 100)).toEqual({ value: curve, source: { kind: "curve" } });
    expect(gradedPrice("p", cgc10, null, null, 100, true)).toEqual({ value: Math.round(curve * 1.6 * 100) / 100, source: { kind: "premium" } });
    expect(gradedPrice("p", cgc10, null, null, null, true)).toBeNull();
    // Pristine on anything but a CGC 10 is ignored.
    expect(gradedPrice("p", { company: "PSA", grade: "10" }, null, ebay(), 100, true)).toEqual(gradedPrice("p", { company: "PSA", grade: "10" }, null, ebay(), 100));

    expect(gradedLookup("p", 100, cgc10, ebay(), pc, true).detail).toBe("Median of 2 CGC Pristine 10 eBay sales this month");
    expect(gradedLookup("p", 100, cgc10, ebay(), pc).detail).toBe("Median of 3 CGC Gem Mint 10 eBay sales this month");
    expect(gradedLookup("p", 100, cgc10, null, pc).detail).toBe("PriceCharting · CGC Gem Mint 10");
    expect(gradedLookup("p", 100, cgc10, null, pc, true).detail).toBe("Estimate · CGC Gem Mint 10 price × 1.6, the usual Pristine premium");
  });

  it("scores Sells fast on one kind's sales", () => {
    expect(sellSpeed(ebay(), "CGC 10", TODAY, true)).toEqual({ score: 60, tier: "Sells steady", segments: 2, sold: 2 });
    expect(sellSpeed(ebay(), "CGC 10", TODAY, false)).toEqual({ score: 64, tier: "Sells steady", segments: 2, sold: 3 });
    expect(sellSpeed(ebay(), CGC_PRISTINE_10, TODAY)).toEqual(sellSpeed(ebay(), "CGC 10", TODAY, true));
    // Without it, a CGC 10 is scored on every CGC 10 sale, as before.
    expect(sellSpeed(ebay(), "CGC 10", TODAY)).toEqual({ score: 56, tier: "Sells steady", segments: 2, sold: 5 });
    // A Pristine with one sale isn't enough to go on.
    const one = ebay([sale(1500, "2026-10-28", "Charizard CGC Pristine 10"), sale(900, "2026-10-25", "CGC 10")]);
    expect(sellSpeed(one, "CGC 10", TODAY, true)).toBeNull();
  });
});

describe("a Pristine slab in the collection", () => {
  const raw: NormalizedPrice = { productId: "p1", printing: null, market: 100, low: null, change24hPct: null, change7dPct: null, change30dPct: null, updatedAt: null, fetchedAt: null, source: "tcgapi", status: "live" };
  const slab: Transaction = { id: "t1", type: "purchase", date: "2026-01-01", productId: "p1", printing: null, condition: "Near Mint", grade: { company: "CGC", grade: "10" }, quantity: 1, unitPrice: 300, fees: 0, shipping: 0, tax: 0, createdAt: "" };
  const data = (over: Partial<CollectionData> = {}): CollectionData => ({
    products: {},
    transactions: [slab],
    watchlist: [],
    prices: { [priceKey("p1", null)]: raw },
    history: {},
    manualValues: {},
    preferences: { currency: "USD", defaultView: "grid", chartRange: "1M" },
    ...over,
  });
  const sales = { [priceKey("p1", null)]: ebay() };

  it("is priced from Pristine sales under its own key", () => {
    const marked = data({ pristineSlabs: [holdingKey(slab)] });
    expect(holdingPriceKey(marked, slab)).toBe("p1||CGC Pristine 10");
    expect(holdingPriceKey(data(), slab)).toBe(gradedPriceKey("p1", null, slab.grade!));
    const out = withEbayGradedPrices(marked, sales, TODAY);
    expect(out.prices["p1||CGC Pristine 10"]?.market).toBe(1600);
    expect(new PriceResolver(out, TODAY).resolve(slab, TODAY)?.price).toBe(1600);
    // Unmarked: the Gem Mint 10 median.
    const plain = withEbayGradedPrices(data(), sales, TODAY);
    expect(new PriceResolver(plain, TODAY).resolve(slab, TODAY)?.price).toBe(950);
    // Too few Pristine sales: Gem Mint × 1.6.
    const few = { [priceKey("p1", null)]: ebay([sale(1500, "2026-10-28", "Pristine"), sale(900, "2026-10-25", "CGC 10"), sale(1000, "2026-10-18", "CGC 10")]) };
    expect(new PriceResolver(withEbayGradedPrices(marked, few, TODAY), TODAY).resolve(slab, TODAY)?.price).toBe(1520);
  });

  it("gets the premium on demo prices too", () => {
    const demo: Transaction = { ...slab, productId: "sample:p1" };
    const base = data({ transactions: [demo], prices: { [priceKey("sample:p1", null)]: { ...raw, productId: "sample:p1" } } });
    const gem = withSampleGradedPrices(base, TODAY).prices[gradedPriceKey("sample:p1", null, demo.grade!)]!.market!;
    const pri = withSampleGradedPrices({ ...base, pristineSlabs: [holdingKey(demo)] }, TODAY).prices["sample:p1||CGC Pristine 10"]!.market!;
    // Each key has its own small wobble, so within a few percent.
    expect(pri / gem).toBeCloseTo(1.6, 1);
  });
});
