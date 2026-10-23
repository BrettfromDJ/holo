import { describe, expect, it } from "vitest";
import { estimateSale, fifoCost } from "../sell";

const lots = [
  { quantity: 1, unitCost: 100 },
  { quantity: 2, unitCost: 150 },
];

describe("estimateSale", () => {
  it("uses FIFO cost and applies percentage + fixed fees to the order total", () => {
    const e = estimateSale(lots, { quantity: 2, unitPrice: 200, fees: { percent: 10, fixed: 0.5 }, shippingCharged: 10, shippingCost: 8 });
    expect(fifoCost(lots, 2)).toBe(250);
    expect(e.gross).toBe(400);
    expect(e.platformFees).toBeCloseTo(41.5); // 10% of 410 + 0.50
    expect(e.net).toBeCloseTo(400 + 10 - 41.5 - 8);
    expect(e.costBasis).toBe(250);
    expect(e.profit).toBeCloseTo(110.5);
  });

  it("break-even price yields zero profit", () => {
    const input = { quantity: 3, unitPrice: 0, fees: { percent: 13.25, fixed: 0.4 }, shippingCharged: 5, shippingCost: 12 };
    const be = estimateSale(lots, input).breakEvenUnitPrice!;
    expect(estimateSale(lots, { ...input, unitPrice: be }).profit).toBeCloseTo(0, 8);
  });

  it("clamps to units held and charges no fees when nothing is sold", () => {
    const e = estimateSale(lots, { quantity: 10, unitPrice: 100, fees: { percent: 0, fixed: 0 }, shippingCharged: 0, shippingCost: 0 });
    expect(e.quantity).toBe(3);
    expect(e.costBasis).toBe(400);
    const none = estimateSale([], { quantity: 1, unitPrice: 100, fees: { percent: 10, fixed: 1 }, shippingCharged: 0, shippingCost: 0 });
    expect(none.platformFees).toBe(0);
    expect(none.breakEvenUnitPrice).toBeNull();
  });
});
