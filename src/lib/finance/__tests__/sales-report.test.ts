import { describe, expect, it } from "vitest";
import { buildLedger } from "../ledger";
import { heldOverAYear, salesCsv, salesLines, salesTotals, salesYears } from "../sales-report";
import { tx } from "./fixtures";

describe("sales report", () => {
  const log = [
    tx({ id: "b1", type: "purchase", date: "2024-03-01", quantity: 2, unitPrice: 100, fees: 10 }),
    tx({ id: "b2", type: "purchase", date: "2025-06-01", quantity: 2, unitPrice: 150 }),
    tx({ id: "s1", type: "sale", date: "2025-07-01", quantity: 3, unitPrice: 200, fees: 30 }),
    tx({ id: "a1", type: "adjustment", date: "2025-08-01", quantity: -1, unitPrice: 0 }),
  ];

  it("splits a sale by purchase date, oldest first, with each part's term", () => {
    const lines = salesLines(log);
    expect(lines).toHaveLength(2);
    const [first, second] = [...lines].sort((a, b) => a.id.localeCompare(b.id));
    expect(first).toMatchObject({ saleId: "s1", acquired: "2024-03-01", quantity: 2, longTerm: true });
    expect(first.cost).toBeCloseTo(210);
    expect(first.proceeds).toBeCloseTo(380);
    expect(second).toMatchObject({ acquired: "2025-06-01", quantity: 1, longTerm: false });
    expect(second.gain).toBeCloseTo(190 - 150);
  });

  it("adds up to the ledger's realized sale gain", () => {
    const t = salesTotals(salesLines(log));
    const ledgerSales = [...buildLedger(log).positions.values()].flatMap((p) => p.realized).filter((r) => r.kind === "sale");
    expect(t.gain).toBeCloseTo(ledgerSales.reduce((s, r) => s + r.gain, 0));
    expect(t.sales).toBe(1);
    expect(t.quantity).toBe(3);
    expect(t.longTermGain + t.shortTermGain).toBeCloseTo(t.gain);
  });

  it("lists years and writes a CSV", () => {
    const lines = salesLines(log);
    expect(salesYears(lines)).toEqual([2025]);
    const csv = salesCsv(lines, { "p:box": { name: 'Box, "big"', setName: "Set" } as never });
    expect(csv.split("\n")[1]).toContain('"Box, ""big"""');
    expect(csv).toContain(",Long\n");
  });

  it("counts long term only after the first anniversary", () => {
    expect(heldOverAYear("2024-03-01", "2025-03-01")).toBe(false);
    expect(heldOverAYear("2024-03-01", "2025-03-02")).toBe(true);
  });
});
