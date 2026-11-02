import { describe, expect, it } from "vitest";
import { canFuzz, damerauLevenshtein, fuzzyAnchors, fuzzyDistance, fuzzyFilter, matchesNumber, numberPatterns, parseNumberToken, splitNumber } from "./search-match";

describe("collector numbers", () => {
  it("reads the forms collectors type", () => {
    expect(parseNumberToken("215/203")).toEqual({ prefix: "", digits: "215", total: { prefix: "", digits: "203" }, explicit: true });
    expect(parseNumberToken("#215")).toEqual({ prefix: "", digits: "215", total: null, explicit: true });
    expect(parseNumberToken("215")).toEqual({ prefix: "", digits: "215", total: null, explicit: false });
    expect(parseNumberToken("TG05")).toEqual({ prefix: "tg", digits: "5", total: null, explicit: false });
    expect(parseNumberToken("tg05/tg30")).toEqual({ prefix: "tg", digits: "5", total: { prefix: "tg", digits: "30" }, explicit: true });
    expect(parseNumberToken("GG12")?.prefix).toBe("gg");
    expect(parseNumberToken("#007")?.digits).toBe("7");
  });

  it("leaves words, years and versions alone", () => {
    expect(parseNumberToken("umbreon")).toBeNull();
    expect(parseNumberToken("30th")).toBeNull();
    expect(parseNumberToken("2023")).toBeNull();
    expect(parseNumberToken("vmax")).toBeNull();
    expect(parseNumberToken("1/2/3")).toBeNull();
  });

  it("splits the number from the name words", () => {
    expect(splitNumber(["umbreon", "215"])).toMatchObject({ words: ["umbreon"], numberWord: "215" });
    expect(splitNumber(["evolving", "skies"])).toMatchObject({ words: ["evolving", "skies"], number: null });
  });

  it("matches stored numbers whatever their zeros and case", () => {
    const n = parseNumberToken("15")!;
    expect(matchesNumber("015/198", n)).toBe(true);
    expect(matchesNumber("15", n)).toBe(true);
    expect(matchesNumber("150/198", n)).toBe(false);
    expect(matchesNumber("TG15/TG30", n)).toBe(false);
    expect(matchesNumber(null, n)).toBe(false);
    const tg = parseNumberToken("TG05/TG30")!;
    expect(matchesNumber("TG05/TG30", tg)).toBe(true);
    expect(matchesNumber("TG05/TG31", tg)).toBe(false);
    const full = parseNumberToken("215/203")!;
    expect(matchesNumber("215/203", full)).toBe(true);
    expect(matchesNumber("215/198", full)).toBe(false);
    expect(matchesNumber("215", full)).toBe(true);
  });

  it("builds patterns for every zero-padding", () => {
    expect(numberPatterns(parseNumberToken("15")!)).toEqual(["15", "15/*", "015", "015/*", "0015", "0015/*"]);
    expect(numberPatterns(parseNumberToken("tg5")!)).toContain("tg05/*");
  });
});

describe("typo tolerance", () => {
  it("counts edits, with a swap as one", () => {
    expect(damerauLevenshtein("charzard", "charizard")).toBe(1);
    expect(damerauLevenshtein("vmx", "vmax")).toBe(1);
    expect(damerauLevenshtein("umbroen", "umbreon")).toBe(1);
    expect(damerauLevenshtein("pikachu", "pikachu")).toBe(0);
    expect(damerauLevenshtein("abc", "xyz")).toBe(3);
    expect(damerauLevenshtein("a", "abcdef", 2)).toBe(3);
  });

  it("only guesses at long enough words", () => {
    expect(canFuzz(["ex", "vmx"])).toBe(false);
    expect(canFuzz(["charzard"])).toBe(true);
    expect(fuzzyAnchors("chrizard")).toEqual(["chr", "ard"]);
    expect(fuzzyAnchors("vmx")).toEqual(["vm", "mx"]);
  });

  it("finds close names and leaves the rest", () => {
    expect(fuzzyDistance("Charizard ex Obsidian Flames", ["charzard"])).toBe(1);
    expect(fuzzyDistance("Umbreon VMAX (Alternate Art Secret) Evolving Skies", ["umbreon", "vmx"])).toBe(1);
    expect(fuzzyDistance("Umbreon V Evolving Skies", ["umbreon", "vmx"])).toBeNull();
    expect(fuzzyDistance("Charmander", ["charzard"])).toBeNull();
    // Long words may be two edits off.
    expect(fuzzyDistance("Prismatic Evolutions", ["prismatik", "evolutoins"])).toBe(2);
  });

  it("keeps close matches, closest first", () => {
    const names = ["Charmeleon", "Charizard VMAX", "Charizard ex", "Pikachu"];
    expect(fuzzyFilter(names, ["charizrd"], (n) => n)).toEqual(["Charizard VMAX", "Charizard ex"]);
    expect(fuzzyFilter(["Umbreon V", "Umbreon VMAX", "Umbreon VSTAR"], ["umbreon", "vmx"], (n) => n)).toEqual(["Umbreon VMAX"]);
  });
});
