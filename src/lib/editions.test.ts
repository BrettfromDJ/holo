import { describe, expect, it } from "vitest";
import { editionArtName, editionName, editionOf, editionSlug, isEditionSet, parseEditionSlug } from "./editions";
import { setArtFor } from "./set-art";
import { ownedSets } from "./checklists";
import type { HoldingView } from "./finance/portfolio";

describe("editions", () => {
  it("knows the old English sets printed in both editions", () => {
    for (const name of ["Base Set", "Jungle", "Fossil", "Team Rocket", "Gym Heroes", "Gym Challenge", "Neo Genesis", "Neo Discovery", "Neo Revelation", "Neo Destiny"]) {
      expect(isEditionSet({ name, gameName: "Pokemon" })).toBe(true);
    }
    expect(isEditionSet({ name: "Base Set 2", gameName: "Pokemon" })).toBe(false);
    expect(isEditionSet({ name: "Base Set (Shadowless)", gameName: "Pokemon" })).toBe(false);
    expect(isEditionSet({ name: "Jungle", gameName: "Pokemon Japan" })).toBe(false);
  });

  it("names, slugs and art for each half", () => {
    expect(editionName("Base Set", "1st-edition")).toBe("Base Set 1st Edition");
    expect(editionName("Jungle", "unlimited")).toBe("Jungle Unlimited");
    expect(parseEditionSlug(editionSlug("base-set", "unlimited"))).toEqual({ slug: "base-set", edition: "unlimited" });
    expect(parseEditionSlug("base-set")).toBeNull();
    const art = (name: string, e: "1st-edition" | "unlimited") => setArtFor({ gameName: "Pokemon", name: editionArtName(name, e) })?.logo.split("/")[3];
    expect(art("Base Set", "1st-edition")).toBe("base-set-1st-edition-bss");
    expect(art("Base Set", "unlimited")).toBe("base-set-unlimited-bs");
    expect(art("Neo Destiny", "1st-edition")).toBe("neo-destiny-1st-edition-n4");
    expect(art("Neo Destiny", "unlimited")).toBe("neo-destiny-n4");
  });

  it("puts each copy in its own edition's master set", () => {
    expect(editionOf("1st Edition Holofoil")).toBe("1st-edition");
    expect(editionOf("Unlimited Holofoil")).toBe("unlimited");
    expect(editionOf(null)).toBe("unlimited");
    const h = (printing: string) =>
      ({ identity: { productId: "tcgapi:1", printing }, product: { kind: "single", source: "tcgapi", setId: "base-set", setName: "Base Set", name: "Charizard" } }) as unknown as HoldingView;
    const sets = ownedSets([h("1st Edition Holofoil"), h("Unlimited Holofoil"), h("Unlimited Holofoil")]);
    expect(sets.map((s) => [s.setId, s.name, s.holdings.length])).toEqual([
      ["base-set--unlimited", "Base Set Unlimited", 2],
      ["base-set--1st-edition", "Base Set 1st Edition", 1],
    ]);
  });
});
