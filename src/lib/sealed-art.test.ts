import { describe, expect, it } from "vitest";
import { sealedArt } from "./sealed-art";

describe("sealedArt", () => {
  it("matches a set's sealed products by name", () => {
    expect(sealedArt({ name: "Delta Reign Elite Trainer Box", setName: "ME03: Delta Reign", kind: "sealed" })).toBe("/products/pokemon/delta-reign/elite-trainer-box.webp");
    expect(sealedArt({ name: "Delta Reign Booster Pack", setName: "Delta Reign", kind: "sealed" })).toBe("/products/pokemon/delta-reign/booster-pack.webp");
    expect(sealedArt({ name: "Delta Reign Build & Battle Box", setName: "Delta Reign", kind: "sealed" })).toBe("/products/pokemon/delta-reign/build-and-battle-box.webp");
    expect(sealedArt({ name: "Delta Reign 3 Pack Blister [Seel]", setName: "Delta Reign", kind: "sealed" })).toBe("/products/pokemon/delta-reign/3-pack-blister-seel.webp");
  });
  it("prefers the longest listed name (the case, not the box)", () => {
    expect(sealedArt({ name: "Delta Reign Elite Trainer Box Case", setName: "Delta Reign", kind: "sealed" })).toBe("/products/pokemon/delta-reign/elite-trainer-box-case.webp");
    expect(sealedArt({ name: "Mega Evolution: Delta Reign Pokemon Center Elite Trainer Box", setName: "Delta Reign", kind: "sealed" })).toBe("/products/pokemon/delta-reign/pokemon-center-elite-trainer-box-exclusive.webp");
    expect(sealedArt({ name: "Delta Reign Sleeved Booster Pack Art Bundle", setName: "Delta Reign", kind: "sealed" })).toBe("/products/pokemon/delta-reign/sleeved-booster-pack-art-bundle-set-of-4.webp");
  });
  it("leaves singles and other sets alone", () => {
    expect(sealedArt({ name: "Rayquaza ex", setName: "Delta Reign", kind: "single" })).toBeNull();
    expect(sealedArt({ name: "Surging Sparks Booster Box", setName: "Surging Sparks", kind: "sealed" })).toBeNull();
  });
});
