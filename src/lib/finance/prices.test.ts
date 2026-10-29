import { describe, expect, it } from "vitest";
import { priceKey, type HoldingIdentity, type NormalizedPrice } from "../types";
import { PriceResolver } from "./prices";

const today = "2026-10-29";
const quote = { market: 100, status: "live", change24hPct: null } as unknown as NormalizedPrice;
const resolver = new PriceResolver({ prices: { [priceKey("p", null)]: quote }, history: {}, manualValues: {} }, today);
const id = (condition: HoldingIdentity["condition"]): HoldingIdentity => ({ productId: "p", printing: null, condition, grade: null });

describe("price resolver", () => {
  it("prices Near Mint and sealed at market", () => {
    expect(resolver.resolve(id("Near Mint"), today)).toMatchObject({ price: 100, conditionShare: 1 });
    expect(resolver.resolve(id("Sealed"), today)?.price).toBe(100);
  });

  it("estimates played copies as a share of Near Mint", () => {
    expect(resolver.resolve(id("Lightly Played"), today)).toMatchObject({ price: 85, conditionShare: 0.85 });
    expect(resolver.resolve(id("Damaged"), today)?.price).toBe(35);
  });
});
