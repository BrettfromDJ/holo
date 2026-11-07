import { describe, expect, it, vi } from "vitest";
vi.mock("server-only", () => ({}));
import { bigMove } from "./collection-pushes";
import type { HoldingView } from "../finance/portfolio";

const h = (name: string, dayChange: number | null, dayChangePct: number | null, value = 200) =>
  ({ product: { name, id: name }, identity: { productId: name }, dayChange, dayChangePct, value }) as unknown as HoldingView;

describe("bigMove", () => {
  it("picks the biggest move that passes 15% and $25", () => {
    const m = bigMove([h("Small", 10, 0.5), h("Mild", 40, 0.1), h("Umbreon VMAX (Alternate Art)", -60, -0.2), h("Charizard", 30, 0.16)]);
    expect(m?.title).toBe("Umbreon VMAX is down 20% today");
    expect(m?.data?.productId).toBe("Umbreon VMAX (Alternate Art)");
  });
  it("stays quiet on an ordinary day", () => {
    expect(bigMove([h("A", 5, 0.02), h("B", null, null)])).toBeNull();
  });
});
