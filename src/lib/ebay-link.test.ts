import { describe, expect, it } from "vitest";
import { ebayListingsUrl, ebaySetWords, ebaySoldUrl } from "./ebay-link";

const q = (url: string) => new URL(url).searchParams.get("_nkw");

describe("ebaySoldUrl", () => {
  it("searches sold listings for the card with its set and number, without bracketed notes", () => {
    const url = ebaySoldUrl({ name: "Umbreon VMAX (Alternate Full Art)", number: "215/203", kind: "single", setName: "SWSH07: Evolving Skies" });
    expect(url).toContain("LH_Sold=1");
    expect(q(url)).toBe("Umbreon VMAX Evolving Skies 215 -psa -bgs -cgc -sgc");
  });
  it("adds the set so reprints don't mix in, and the grade for slabs", () => {
    expect(q(ebaySoldUrl({ name: "Charizard", number: "4/102", kind: "single", setName: "ME: 30th Celebration Classic Collection" }, "PSA 10"))).toBe("Charizard 30th Celebration 4 PSA 10");
    expect(q(ebaySoldUrl({ name: "Charizard ex - 199/165", number: "199/165", kind: "single", setName: "SV: Scarlet & Violet 151" }, "PSA 10"))).toBe("Charizard ex 151 199 PSA 10");
  });
  it("leaves sealed products as they are", () => {
    expect(q(ebaySoldUrl({ name: "Evolving Skies Booster Box", kind: "sealed", setName: "SWSH07: Evolving Skies" }))).toBe("Evolving Skies Booster Box");
  });
});

describe("ebaySetWords", () => {
  it("drops the code prefix and filler", () => {
    expect(ebaySetWords("SV03: Obsidian Flames")).toBe("Obsidian Flames");
    expect(ebaySetWords("Crown Zenith: Galarian Gallery")).toBe("Crown Zenith");
    expect(ebaySetWords("SWSH12.5: Crown Zenith")).toBe("Crown Zenith");
    expect(ebaySetWords(null)).toBe("");
  });
});

describe("ebayListingsUrl", () => {
  it("searches the same words for live listings, cheapest first", () => {
    const p = { name: "Charizard ex - 199/165", number: "199/165", kind: "single", setName: "SV: Scarlet & Violet 151" };
    const url = new URL(ebayListingsUrl(p, "PSA 10"));
    expect(url.searchParams.get("_nkw")).toBe(new URL(ebaySoldUrl(p, "PSA 10")).searchParams.get("_nkw"));
    expect(url.searchParams.get("LH_Sold")).toBeNull();
    expect(url.searchParams.get("_sop")).toBe("15");
  });
});
