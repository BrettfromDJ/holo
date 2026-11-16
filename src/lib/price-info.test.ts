import { describe, expect, it } from "vitest";
import { isStalePrice, priceAge } from "./price-info";

describe("price age", () => {
  const now = Date.parse("2026-11-16T12:00:00Z");
  it("says how old a price is", () => {
    expect(priceAge("2026-11-16T09:00:00Z", now)).toBe("3h ago");
    expect(priceAge("2026-11-14T12:00:00Z", now)).toBe("2d ago");
    expect(priceAge(null, now)).toBeNull();
  });
  it("calls a price stale after 3 days", () => {
    expect(isStalePrice("2026-11-14T12:00:00Z", now)).toBe(false);
    expect(isStalePrice("2026-11-12T12:00:00Z", now)).toBe(true);
    expect(isStalePrice(null, now)).toBe(false);
  });
});
