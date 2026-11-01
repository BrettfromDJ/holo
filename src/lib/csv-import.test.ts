import { describe, expect, it } from "vitest";
import {
  TEMPLATE_CSV,
  coreName,
  detectColumns,
  isConfident,
  matchPrinting,
  normalizeNumber,
  numberFromName,
  parseCondition,
  parseCsv,
  parseDate,
  parseGrade,
  parseImport,
  parsePrice,
  parsePrinting,
  parseQuantity,
  rankCandidates,
  searchQueries,
} from "./csv-import";
import { SAMPLE_PRODUCTS } from "./demo/catalog";

const today = "2026-11-01";

describe("parseCsv", () => {
  it("handles quotes, commas inside quotes, escaped quotes and CRLF", () => {
    const text = 'Name,Price\r\n"Charizard, Base Set","$1,200.00"\r\n"Say ""hi""",5\r\n';
    expect(parseCsv(text)).toEqual([
      ["Name", "Price"],
      ["Charizard, Base Set", "$1,200.00"],
      ['Say "hi"', "5"],
    ]);
  });

  it("keeps newlines inside quoted cells and drops blank lines", () => {
    expect(parseCsv('a,b\n"line 1\nline 2",x\n\n\n')).toEqual([
      ["a", "b"],
      ["line 1\nline 2", "x"],
    ]);
  });

  it("strips a BOM and detects semicolons and tabs", () => {
    expect(parseCsv("﻿Name;Qty\nPikachu;2")).toEqual([
      ["Name", "Qty"],
      ["Pikachu", "2"],
    ]);
    expect(parseCsv("Name\tQty\nPikachu\t2")[1]).toEqual(["Pikachu", "2"]);
  });

  it("keeps a final line without a newline and trims cells", () => {
    expect(parseCsv("a, b\n 1 ,2")).toEqual([
      ["a", "b"],
      ["1", "2"],
    ]);
  });
});

describe("detectColumns", () => {
  it("recognizes aliases case-insensitively", () => {
    const cols = detectColumns(["Card Name", "Expansion", "#", "COND", "Grader", "Grade", "Qty", "Purchase Price (USD)", "Acquired", "Variant"]);
    expect(cols).toEqual({ name: 0, set: 1, number: 2, condition: 3, grader: 4, grade: 5, quantity: 6, price: 7, date: 8, printing: 9 });
  });

  it("handles other spellings", () => {
    expect(detectColumns(["Product", "set_name", "card_number", "count", "cost", "purchase-date", "finish"])).toEqual({
      name: 0,
      set: 1,
      number: 2,
      quantity: 3,
      price: 4,
      date: 5,
      printing: 6,
    });
    expect(detectColumns(["title", "total paid"])).toEqual({ name: 0, total: 1 });
  });
});

describe("parseCondition", () => {
  it("maps abbreviations and full names", () => {
    expect(parseCondition("NM")).toBe("Near Mint");
    expect(parseCondition("near-mint")).toBe("Near Mint");
    expect(parseCondition("Mint")).toBe("Near Mint");
    expect(parseCondition("lp")).toBe("Lightly Played");
    expect(parseCondition("Lightly Played")).toBe("Lightly Played");
    expect(parseCondition("MP")).toBe("Moderately Played");
    expect(parseCondition("Played")).toBe("Moderately Played");
    expect(parseCondition("HP")).toBe("Heavily Played");
    expect(parseCondition("Heavily Played")).toBe("Heavily Played");
    expect(parseCondition("DMG")).toBe("Damaged");
    expect(parseCondition("damaged")).toBe("Damaged");
    expect(parseCondition("Sealed")).toBe("Sealed");
    expect(parseCondition("Near Mint Holofoil")).toBe("Near Mint");
  });

  it("returns null for blank or unknown", () => {
    expect(parseCondition("")).toBeNull();
    expect(parseCondition(undefined)).toBeNull();
    expect(parseCondition("shiny")).toBeNull();
  });
});

describe("parseGrade", () => {
  it("reads separate grader and grade columns", () => {
    expect(parseGrade("PSA", "10")).toEqual({ company: "PSA", grade: "10" });
    expect(parseGrade("Beckett", "9.5")).toEqual({ company: "BGS", grade: "9.5" });
  });

  it("detects a graded value in a single cell", () => {
    expect(parseGrade(undefined, "PSA 10")).toEqual({ company: "PSA", grade: "10" });
    expect(parseGrade(undefined, "psa10")).toEqual({ company: "PSA", grade: "10" });
    expect(parseGrade(undefined, "BGS 9.5 Black Label")).toEqual({ company: "BGS", grade: "9.5" });
    expect(parseGrade(undefined, "CGC Pristine 10")).toEqual({ company: "CGC", grade: "10" });
    expect(parseGrade("CGC 9", "")).toEqual({ company: "CGC", grade: "9" });
  });

  it("ignores raw, blank, and grades with no company", () => {
    expect(parseGrade("", "")).toBeNull();
    expect(parseGrade("", "Raw")).toBeNull();
    expect(parseGrade("PSA", "ungraded")).toBeNull();
    expect(parseGrade("", "9")).toBeNull();
    expect(parseGrade(undefined, "NM")).toBeNull();
  });
});

describe("parsePrice", () => {
  it("strips currency symbols and thousands separators", () => {
    expect(parsePrice("$1,234.50")).toBe(1234.5);
    expect(parsePrice("USD 12")).toBe(12);
    expect(parsePrice(" 7.99 $ ")).toBe(7.99);
    expect(parsePrice("12,50")).toBe(12.5);
    expect(parsePrice("0")).toBe(0);
  });

  it("returns null for blank, negative or junk", () => {
    expect(parsePrice("")).toBeNull();
    expect(parsePrice("-5")).toBeNull();
    expect(parsePrice("free")).toBeNull();
  });
});

describe("parseQuantity", () => {
  it("defaults to 1 and reads x3", () => {
    expect(parseQuantity("")).toBe(1);
    expect(parseQuantity(undefined)).toBe(1);
    expect(parseQuantity("3")).toBe(3);
    expect(parseQuantity("x3")).toBe(3);
    expect(parseQuantity("1,000")).toBe(1000);
  });
  it("rejects zero, negatives and fractions", () => {
    expect(parseQuantity("0")).toBeNull();
    expect(parseQuantity("-1")).toBeNull();
    expect(parseQuantity("1.5")).toBeNull();
  });
});

describe("parseDate", () => {
  it("accepts common formats", () => {
    expect(parseDate("2024-03-14")).toBe("2024-03-14");
    expect(parseDate("2024-03-14T10:22:00Z")).toBe("2024-03-14");
    expect(parseDate("2024/3/4")).toBe("2024-03-04");
    expect(parseDate("3/4/2024")).toBe("2024-03-04");
    expect(parseDate("3/4/24")).toBe("2024-03-04");
    expect(parseDate("25/12/2023")).toBe("2023-12-25");
    expect(parseDate("25.12.2023")).toBe("2023-12-25");
    expect(parseDate("Jan 5, 2024")).toBe("2024-01-05");
    expect(parseDate("5 January 2024")).toBe("2024-01-05");
    expect(parseDate("12/31/2023 14:00")).toBe("2023-12-31");
  });
  it("rejects impossible or unreadable dates", () => {
    expect(parseDate("2023-02-30")).toBeNull();
    expect(parseDate("13/13/2023")).toBeNull();
    expect(parseDate("yesterday")).toBeNull();
    expect(parseDate("")).toBeNull();
  });
});

describe("printings", () => {
  it("normalizes printing names", () => {
    expect(parsePrinting("Holo")).toBe("Holofoil");
    expect(parsePrinting("Reverse Holo")).toBe("Reverse Holofoil");
    expect(parsePrinting("reverse-holofoil")).toBe("Reverse Holofoil");
    expect(parsePrinting("Non-Holo")).toBe("Normal");
    expect(parsePrinting("1st Edition")).toBe("1st Edition");
    expect(parsePrinting("1st Ed Holo")).toBe("1st Edition Holofoil");
    expect(parsePrinting("")).toBeNull();
  });

  it("matches the product's printings", () => {
    expect(matchPrinting("Holofoil", ["Holofoil", "Reverse Holofoil"])).toEqual({ printing: "Holofoil", matched: true });
    expect(matchPrinting("Holofoil", ["Reverse Holofoil", "Unlimited Holofoil"])).toEqual({ printing: "Unlimited Holofoil", matched: true });
    expect(matchPrinting("1st Edition", ["1st Edition Holofoil", "Unlimited Holofoil"])).toEqual({ printing: "1st Edition Holofoil", matched: true });
    expect(matchPrinting("Reverse Holofoil", ["Normal"], "Normal")).toEqual({ printing: "Normal", matched: false });
    expect(matchPrinting(null, ["Normal", "Holofoil"], "Holofoil")).toEqual({ printing: "Holofoil", matched: true });
  });
});

describe("numbers and names", () => {
  it("normalizes collector numbers", () => {
    expect(normalizeNumber("199/165")).toBe("199");
    expect(normalizeNumber("025")).toBe("25");
    expect(normalizeNumber("SV049")).toBe("sv49");
    expect(normalizeNumber("#4")).toBe("4");
    expect(normalizeNumber(null)).toBeNull();
  });
  it("reads a number at the end of a name", () => {
    expect(numberFromName("Charizard ex - 199/165")).toBe("199/165");
    expect(numberFromName("Pikachu #25")).toBe("25");
    expect(numberFromName("Evolving Skies Booster Box")).toBeNull();
    expect(coreName("Charizard ex - 199/165")).toBe("charizard ex");
  });
});

describe("parseImport", () => {
  it("parses the template", () => {
    const r = parseImport(TEMPLATE_CSV, today);
    expect(r.error).toBeNull();
    expect(r.rows).toHaveLength(3);
    expect(r.rows[1]).toMatchObject({ name: "Umbreon VMAX (Alternate Full Art)", grade: { company: "PSA", grade: "10" }, condition: null, unitPrice: 1250, date: "2024-06-02" });
    expect(r.rows[2]).toMatchObject({ condition: "Sealed", quantity: 2, unitPrice: 640, date: "2023-01-15", number: null });
  });

  it("divides a total by quantity and defaults date and quantity", () => {
    const r = parseImport("Card,Qty,Total\nPikachu,4,$10.00\nMew,,", today);
    expect(r.rows[0]).toMatchObject({ quantity: 4, unitPrice: 2.5, date: today });
    expect(r.rows[1]).toMatchObject({ quantity: 1, unitPrice: null, date: today, warnings: [] });
  });

  it("detects a grade in the condition column", () => {
    const r = parseImport("Name,Condition\nCharizard,PSA 9\nBlastoise,LP", today);
    expect(r.rows[0]).toMatchObject({ grade: { company: "PSA", grade: "9" }, condition: null });
    expect(r.rows[1]).toMatchObject({ grade: null, condition: "Lightly Played" });
  });

  it("skips rows without a name or with a bad quantity, and warns about the rest", () => {
    const r = parseImport("Name,Qty,Date,Condition\n,1,,\nMew,abc,,\nPikachu,1,2099-01-01,Shiny", today);
    expect(r.skipped.map((s) => s.line)).toEqual([2, 3]);
    expect(r.rows[0].date).toBe(today);
    expect(r.rows[0].warnings).toHaveLength(2);
  });

  it("explains a missing name column", () => {
    expect(parseImport("Foo,Bar\n1,2", today).error).toMatch(/name column/);
    expect(parseImport("", today).error).toMatch(/empty/);
  });
});

describe("matching", () => {
  const hits = SAMPLE_PRODUCTS.map((p) => ({ product: p }));

  it("prefers the candidate whose number and set match", () => {
    const ranked = rankCandidates({ name: "Charizard ex", set: "Obsidian Flames", number: "223/197" }, hits);
    expect(ranked[0].product.id).toBe("sample:charizard-ex-of");
    expect(isConfident(ranked[0].fit)).toBe(true);
    const by151 = rankCandidates({ name: "Charizard ex", set: "Scarlet & Violet 151", number: null }, hits);
    expect(by151[0].product.id).toBe("sample:charizard-ex-151");
  });

  it("is confident when every word matches, even if the product name is longer", () => {
    const ranked = rankCandidates({ name: "Umbreon VMAX", set: "Evolving Skies", number: "215/203" }, hits);
    expect(ranked[0].product.id).toBe("sample:umbreon-vmax-alt");
    expect(isConfident(ranked[0].fit)).toBe(true);
    const wrongSet = rankCandidates({ name: "Umbreon VMAX", set: "Brilliant Stars", number: null }, hits);
    expect(isConfident(wrongSet[0].fit)).toBe(false);
  });

  it("matches sealed products by name", () => {
    const ranked = rankCandidates({ name: "Evolving Skies Booster Box", set: null, number: null }, hits);
    expect(ranked[0].product.id).toBe("sample:es-bb");
  });

  it("returns nothing for unknown cards", () => {
    expect(rankCandidates({ name: "Totally Made Up Card", set: null, number: null }, hits)).toEqual([]);
  });

  it("builds search queries from specific to loose", () => {
    expect(searchQueries({ name: "Charizard ex", set: "Obsidian Flames", number: "223/197" })).toEqual(["charizard ex 223/197", "charizard ex obsidian flames", "charizard ex"]);
  });
});
