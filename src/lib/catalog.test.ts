import { describe, expect, it } from "vitest";
import { inferKind, looksSealed } from "./catalog";

const kind = (name: string, productType: string | null = "Cards", number: string | null = null) => inferKind({ name, productType, number });

describe("inferKind", () => {
  it("treats unmistakably sealed names as sealed even if the source says Cards", () => {
    expect(kind("First Partner Illustration Collection (Series 1)")).toBe("sealed");
    expect(kind("Prismatic Evolutions Booster Bundle", "Cards", "123")).toBe("sealed");
    expect(kind("Scarlet & Violet—151 Elite Trainer Box")).toBe("sealed");
    expect(kind("Paldean Fates Tin")).toBe("sealed");
    expect(kind("Surging Sparks 3 Pack Blister")).toBe("sealed");
    expect(kind("Build & Battle Box")).toBe("sealed");
  });

  it("keeps cards as singles, including parenthetical set names", () => {
    expect(kind("Charizard (Classic Collection)", "Cards", "4/102")).toBe("single");
    expect(kind("Umbreon VMAX (Alternate Full Art)", null, "215/203")).toBe("single");
    expect(kind("Pikachu ex - 238/191", null, "238/191")).toBe("single");
    expect(looksSealed("Tinkatuff")).toBe(false);
  });

  it("respects an explicit hint and the source's sealed type", () => {
    expect(inferKind({ name: "Mystery Item", productType: null, number: null }, "sealed")).toBe("sealed");
    expect(kind("Mystery Item", "Sealed Products")).toBe("sealed");
  });
});
