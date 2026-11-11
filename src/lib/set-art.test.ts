import { describe, expect, it } from "vitest";
import { setArtFor } from "./set-art";

const slugOf = (name: string, gameName = "Pokemon") => setArtFor({ gameName, name })?.background.split("/")[3] ?? null;

describe("set artwork", () => {
  it("matches the catalog's set names to our folders", () => {
    expect(slugOf("SWSH12.5: Crown Zenith")).toBe("crown-zenith-crz");
    expect(slugOf("Crown Zenith")).toBe("crown-zenith-crz");
    expect(slugOf("SWSH07: Evolving Skies")).toBe("evolving-skies-swsh07");
    expect(slugOf("SV: Scarlet & Violet 151")).toBe("pokemon-card-151-mew");
    expect(slugOf("SV01: Scarlet & Violet Base Set")).toBe("scarlet-and-violet-base-svi");
    expect(slugOf("SV: Scarlet & Violet Promo Cards")).toBe("scarlet-and-violet-promos-svp");
    expect(slugOf("SWSH01: Sword & Shield Base Set")).toBe("sword-and-shield-swsh01");
    expect(slugOf("SM - Guardians Rising")).toBe("guardians-rising-sm02");
    expect(slugOf("SM Base Set")).toBe("sun-and-moon-sm01");
    expect(slugOf("XY Base Set")).toBe("xy-base-xy");
    expect(slugOf("XY Promos")).toBe("xy-black-star-promos-pr");
    expect(slugOf("Base Set")).toBe("base-set-unlimited-bs");
    expect(slugOf("Base Set (Shadowless)")).toBe("base-set-shadowless-bss");
    expect(slugOf("Base Set 2")).toBe("base-set-2-bs2");
    expect(slugOf("FireRed & LeafGreen")).toBe("fire-red-leaf-green-rg");
    expect(slugOf("Expedition Base Set")).toBe("expedition-ex");
    expect(slugOf("Celebrations: Classic Collection")).toBe("celebrations-classic-collection-ccc");
    expect(slugOf("Celebrations")).toBe("celebrations-clb");
    expect(slugOf("ME01: Mega Evolution")).toBe("mega-evolution-meg");
    expect(slugOf("ME02: Phantasmal Flames")).toBe("phantasmal-flames-pfl");
    expect(slugOf("SV: Prismatic Evolutions")).toBe("prismatic-evolutions-pre");
  });

  it("matches Japanese sets by their code, then by name", () => {
    const ja = (name: string, abbreviation?: string) => setArtFor({ gameName: "Pokemon Japan", name, abbreviation })?.background.split("/")[3] ?? null;
    expect(setArtFor({ gameName: "Pokemon Japan", name: "M2a: MEGA Dream ex" })?.background).toBe("/sets/pokemon-japan/mega-dream-m2a/background.webp");
    expect(ja("MEGA Dream ex")).toBe("mega-dream-m2a");
    expect(ja("SV2a: Pokemon Card 151")).toBe("pokemon-card-151-japanese-sv2a");
    expect(ja("SV11B: Black Bolt")).toBe("black-bolt-japanese-sv11b");
    expect(ja("S8a: 25th Anniversary Collection")).toBe("25th-anniversary-collection-s8a");
    expect(ja("SV4a: Shiny Treasure ex")).toBe("shiny-treasure-ex-sv4a");
    expect(ja("S12a: VSTAR Universe")).toBe("vstar-universe-s12a");
    expect(ja("Eevee Heroes", "S6a")).toBe("eevee-heroes-s6a");
    // A code several decks share falls back to the name.
    expect(ja("BW5: Dragon Blade")).toBe("dragon-blade-bw5");
    expect(ja("BW5: Dragon Blast")).toBe("dragon-blast-bw5");
  });

  it("leaves other games and unknown sets to the catalog's own art", () => {
    expect(slugOf("Crown Zenith", "Pokemon Japan")).toBeNull();
    expect(slugOf("Crown Zenith", "Magic: The Gathering")).toBeNull();
    expect(slugOf("Some New Set")).toBeNull();
  });
});
