import { describe, expect, it } from "vitest";
import { sealedArt } from "./sealed-art";

const s = (name: string, setName: string | null, kind = "sealed") => sealedArt({ name, setName, kind });

describe("sealedArt", () => {
  it("matches a set's sealed products by name", () => {
    expect(s("Delta Reign Elite Trainer Box", "ME03: Delta Reign")).toBe("/products/pokemon/delta-reign/delta-reign-elite-trainer-box.webp");
    expect(s("Delta Reign Build & Battle Box", "Delta Reign")).toBe("/products/pokemon/delta-reign/delta-reign-build-and-battle-box.webp");
    expect(s("Brilliant Stars Booster Box", "SWSH09: Brilliant Stars")).toBe("/products/pokemon/brilliant-stars/brilliant-stars-booster-box.webp");
    expect(s("Arceus V Figure Collection", "SWSH09: Brilliant Stars")).toBe("/products/pokemon/brilliant-stars/arceus-v-figure-collection.webp");
  });
  it("prefers the longest listed name (the case, not the box)", () => {
    expect(s("Delta Reign Elite Trainer Box Case", "Delta Reign")).toBe("/products/pokemon/delta-reign/delta-reign-elite-trainer-box-case.webp");
    expect(s("Surging Sparks Booster Box Case", "SV08: Surging Sparks")).toBe("/products/pokemon/surging-sparks/surging-sparks-booster-box-case.webp");
  });
  it("matches without bracketed notes", () => {
    expect(s("Surging Sparks Booster Bundle", "SV08: Surging Sparks")).toBe("/products/pokemon/surging-sparks/surging-sparks-booster-bundle-retail.webp");
  });
  it("picks the set named last, not the series before it", () => {
    expect(s("Mega Evolution: Delta Reign Booster Box", "Mega Evolution—Delta Reign")).toBe("/products/pokemon/delta-reign/delta-reign-booster-box.webp");
    expect(s("Mega Evolution Booster Box", "ME01: Mega Evolution")).toBe("/products/pokemon/mega-evolution/mega-evolution-booster-box.webp");
    expect(s("Scarlet & Violet 151 Booster Bundle", "SV: Scarlet & Violet 151")).toBe("/products/pokemon/151/151-booster-bundle.webp");
    expect(s("Scarlet & Violet Booster Box", "SV01: Scarlet & Violet Base Set")).toBe("/products/pokemon/scarlet-and-violet-base-set/scarlet-and-violet-booster-box.webp");
  });
  it("leaves singles and other sets alone", () => {
    expect(s("Rayquaza ex", "Delta Reign", "single")).toBeNull();
    expect(s("Base Set Booster Box", "Base Set")).toBeNull();
  });
});
