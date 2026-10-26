import { describe, expect, it } from "vitest";
import { packCount, pricePerPack } from "./packs";

const sealed = (name: string) => ({ name, kind: "sealed" as const });

describe("packCount", () => {
  it("reads explicit counts from the name", () => {
    expect(packCount(sealed("Surging Sparks 3-Pack Blister [Pikachu]"))).toEqual({ packs: 3, exact: true });
    expect(packCount(sealed("Celebrations Booster Box (36 Booster Packs)"))).toEqual({ packs: 36, exact: true });
    expect(packCount(sealed("Paldean Fates Tin (Four Packs)"))).toEqual({ packs: 4, exact: true });
  });

  it("uses standard contents for well-known product types", () => {
    expect(packCount(sealed("Prismatic Evolutions Elite Trainer Box"))?.packs).toBe(9);
    expect(packCount(sealed("Scarlet & Violet—151 Booster Bundle"))?.packs).toBe(6);
    expect(packCount(sealed("Bloomburrow Collector Booster Display"))?.packs).toBe(12);
    expect(packCount(sealed("Bloomburrow Play Booster Box"))?.packs).toBe(36);
    expect(packCount(sealed("Journey Together Booster Pack"))?.packs).toBe(1);
  });

  it("only sizes booster boxes when the game is known", () => {
    expect(packCount(sealed("Surging Sparks Booster Box"))).toBeNull();
    expect(packCount(sealed("Surging Sparks Booster Box"), "pokemon")?.packs).toBe(36);
    expect(packCount(sealed("Terastal Festival ex Booster Box"), "pokemon-japan")?.packs).toBe(30);
    expect(packCount(sealed("Phantom Nightmare Booster Box"), "yugioh")?.packs).toBe(24);
    expect(packCount(sealed("Romance Dawn Booster Box"), "one-piece-card-game")?.packs).toBe(24);
  });

  it("skips singles, cases and things it can't size", () => {
    expect(packCount({ name: "Umbreon VMAX", kind: "single" })).toBeNull();
    expect(packCount(sealed("Evolving Skies Booster Box Case"), "pokemon")).toBeNull();
    expect(packCount(sealed("Charizard ex Premium Collection"))).toBeNull();
  });

  it("divides price across packs", () => {
    expect(pricePerPack(180, { packs: 36, exact: false })).toBe(5);
    expect(pricePerPack(null, { packs: 36, exact: false })).toBeNull();
  });
});
