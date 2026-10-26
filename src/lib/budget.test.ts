import { describe, expect, it } from "vitest";
import { budgetStatus } from "./budget";
import type { Transaction } from "./types";

const tx = (id: string, date: string, unitPrice: number, extra: Partial<Transaction> = {}): Transaction => ({
  id,
  type: "purchase",
  productId: "p",
  printing: null,
  condition: "Sealed",
  grade: null,
  date,
  quantity: 1,
  unitPrice,
  fees: 0,
  shipping: 0,
  tax: 0,
  createdAt: `${date}T00:00:00Z`,
  ...extra,
});

describe("budgetStatus", () => {
  it("counts this month's purchases with fees, shipping and tax", () => {
    const s = budgetStatus([tx("a", "2026-10-02", 100, { shipping: 10, tax: 5 }), tx("b", "2026-10-20", 50), tx("c", "2026-09-30", 999)], "2026-10-26", 200);
    expect(s.spent).toBe(165);
    expect(s.remaining).toBe(35);
    expect(s.used).toBeCloseTo(0.825);
    expect(s.purchases).toBe(2);
  });

  it("ignores voided purchases and sales", () => {
    const s = budgetStatus(
      [tx("a", "2026-10-02", 100), { ...tx("v", "2026-10-03", 0), type: "correction", correctsId: "a", quantity: 0 }, { ...tx("s", "2026-10-04", 300), type: "sale" }],
      "2026-10-26",
      100,
    );
    expect(s.spent).toBe(0);
  });

  it("works without a budget", () => {
    const s = budgetStatus([tx("a", "2026-10-13", 130)], "2026-10-13", null);
    expect(s.remaining).toBeNull();
    expect(s.projected).toBeCloseTo(310);
  });
});
