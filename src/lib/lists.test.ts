import { describe, expect, it } from "vitest";
import { askingPrice, listIdFromShareTitle, listShareTitle, parseListMeta } from "./lists";

describe("lists", () => {
  it("asks your own price first, then market times the percentage", () => {
    const meta = { forSale: true, askPercent: 90, prices: { a: 50 } };
    expect(askingPrice(meta, "a", 100)).toBe(50);
    expect(askingPrice(meta, "b", 100)).toBe(90);
    expect(askingPrice(meta, "b", 33.33)).toBe(30);
    expect(askingPrice(meta, "b", null)).toBeNull();
    expect(askingPrice(undefined, "b", 12.34)).toBe(12.34);
  });

  it("round-trips share titles", () => {
    expect(listIdFromShareTitle(listShareTitle("abc"))).toBe("abc");
    expect(listIdFromShareTitle("My collection")).toBeNull();
    expect(listIdFromShareTitle(null)).toBeNull();
  });

  it("drops malformed meta", () => {
    expect(parseListMeta(null)).toEqual({});
    expect(parseListMeta({ x: { forSale: true, askPercent: 0, prices: { a: -1, b: 4 } } })).toEqual({ x: { forSale: true, askPercent: null, prices: { b: 4 } } });
  });
});
