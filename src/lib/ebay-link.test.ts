import { describe, expect, it } from "vitest";
import { ebaySoldUrl } from "./ebay-link";

const q = (url: string) => new URL(url).searchParams.get("_nkw");

describe("ebaySoldUrl", () => {
  it("searches sold listings for the card, without bracketed notes, adding its number", () => {
    const url = ebaySoldUrl({ name: "Umbreon VMAX (Alternate Full Art)", number: "215/203", kind: "single" });
    expect(url).toContain("LH_Sold=1");
    expect(q(url)).toBe("Umbreon VMAX 215/203 -psa -bgs -cgc -sgc");
  });
  it("doesn't repeat a number already in the name, and adds the grade for slabs", () => {
    expect(q(ebaySoldUrl({ name: "Charizard ex - 199/165", number: "199/165", kind: "single" }, "PSA 10"))).toBe("Charizard ex 199/165 PSA 10");
  });
  it("leaves sealed products as they are", () => {
    expect(q(ebaySoldUrl({ name: "Evolving Skies Booster Box", kind: "sealed" }))).toBe("Evolving Skies Booster Box");
  });
});
