import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
import { gradeColumn, guideRows, money, parseCsv } from "./pricecharting";

describe("PriceCharting price guide", () => {
  it("reads quoted CSV fields", () => {
    expect(parseCsv('a,b\n"x, y","he said ""hi"""\n')).toEqual([
      ["a", "b"],
      ["x, y", 'he said "hi"'],
    ]);
  });

  it("reads dollar amounts and treats blanks as no price", () => {
    expect(money("$1,234.56")).toBe(1234.56);
    expect(money("")).toBeNull();
    expect(money("0")).toBeNull();
  });

  it("keeps only cards with a TCGplayer id and maps the grade columns", () => {
    const csv = [
      "id,console-name,product-name,loose-price,cib-price,new-price,graded-price,box-only-price,manual-only-price,bgs-10-price,condition-17-price,condition-18-price,sales-volume,tcg-id",
      "1,Pokemon Base Set,Charizard #4,$300.00,$500.00,$700.00,$1000.00,$1500.00,$9000.00,$20000.00,$8000.00,$7000.00,120,42382",
      "2,Pokemon 1998 KFC,Pikachu #25,$20.00,,,,,,,,,10,",
    ].join("\n");
    const rows = guideRows(csv);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ pc_id: 1, tcg_id: 42382, ungraded: 300, grade_9: 1000, grade_9_5: 1500, psa_10: 9000, bgs_10: 20000, cgc_10: 8000, sgc_10: 7000 });
  });

  it("matches a slab to its column", () => {
    expect(gradeColumn("PSA", "10")).toBe("psa_10");
    expect(gradeColumn("cgc", "10")).toBe("cgc_10");
    expect(gradeColumn("BGS", "9.5")).toBe("grade_9_5");
    expect(gradeColumn("PSA", "6")).toBeNull();
  });
});
