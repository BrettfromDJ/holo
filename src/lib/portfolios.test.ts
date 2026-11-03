import { describe, expect, it } from "vitest";
import { applyMainChange, copyTo, filterFor, isIn, membersOf, moveTo, type Membership } from "./portfolios";

// Same cases as the app's PortfolioMembershipTests.swift.
const base = (): Membership => ({
  portfolios: [
    { id: "resale", holdingKeys: ["b"] },
    { id: "kids", holdingKeys: ["c"] },
  ],
  main: [],
});

describe("portfolio membership", () => {
  it("puts holdings in no portfolio in Main", () => {
    const m = base();
    expect(membersOf(m, "a")).toEqual(["main"]);
    expect(membersOf(m, "b")).toEqual(["resale"]);
    expect(isIn(m, "a", "main")).toBe(true);
    expect(isIn(m, "b", "main")).toBe(false);
    expect(isIn(m, "b", "all")).toBe(true);
  });

  it("copies from Main to a portfolio and keeps it in Main", () => {
    const { next, changed, mainAdd } = copyTo(base(), ["a"], "resale");
    expect(next.portfolios[0].holdingKeys).toEqual(["b", "a"]);
    expect(next.main).toEqual(["a"]);
    expect(changed).toEqual(["resale"]);
    expect(mainAdd).toEqual(["a"]);
    expect(membersOf(next, "a")).toEqual(["main", "resale"]);
  });

  it("copies between named portfolios without touching Main", () => {
    const { next } = copyTo(base(), ["b"], "kids");
    expect(membersOf(next, "b")).toEqual(["resale", "kids"]);
    expect(next.main).toEqual([]);
  });

  it("copies to Main", () => {
    const { next } = copyTo(base(), ["b"], "main");
    expect(next.main).toEqual(["b"]);
    expect(membersOf(next, "b")).toEqual(["main", "resale"]);
    // Already in Main: nothing to write.
    const again = copyTo(next, ["a"], "main");
    expect(again.changed).toEqual([]);
    expect(again.mainAdd).toEqual([]);
  });

  it("moves to a portfolio: only there afterwards", () => {
    const copied = copyTo(copyTo(base(), ["b"], "kids").next, ["b"], "main").next;
    expect(membersOf(copied, "b")).toEqual(["main", "resale", "kids"]);
    const { next, changed, mainRemove } = moveTo(copied, ["b"], "kids");
    expect(membersOf(next, "b")).toEqual(["kids"]);
    expect(changed).toEqual(["resale"]);
    expect(mainRemove).toEqual(["b"]);
  });

  it("moves to Main: out of every named portfolio and the Main list", () => {
    const copied = copyTo(base(), ["a"], "resale").next;
    const { next } = moveTo(copied, ["a", "c"], "main");
    expect(next.portfolios.map((p) => p.holdingKeys)).toEqual([["b"], []]);
    expect(next.main).toEqual([]);
    expect(membersOf(next, "a")).toEqual(["main"]);
    expect(membersOf(next, "c")).toEqual(["main"]);
  });

  it("filters each portfolio to everything listed in it", () => {
    const m = copyTo(base(), ["a"], "resale").next;
    const keys = ["a", "b", "c", "d"];
    expect(filterFor(m, "all")).toBeNull();
    expect(keys.filter(filterFor(m, "main")!)).toEqual(["a", "d"]);
    expect(keys.filter(filterFor(m, "resale")!)).toEqual(["a", "b"]);
    expect(keys.filter(filterFor(m, "kids")!)).toEqual(["c"]);
    expect(keys.filter(filterFor(m, "gone")!)).toEqual([]);
  });

  it("merges Main list changes onto the account's list", () => {
    expect(applyMainChange(["x", "a"], ["a", "b"], ["x"])).toEqual(["a", "b"]);
  });
});
