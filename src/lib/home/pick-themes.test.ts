import { describe, expect, it } from "vitest";
import type { Theme } from "@/lib/explore/themes";
import type { ExploreProduct } from "@/lib/explore/types";
import { filteredThemes, fitsFilter, pickThemes, seededRandom, uniqueHits } from "./pick-themes";

const hit = (id: string, releaseDate: string | null): ExploreProduct => ({
  product: { id, source: "tcgapi", externalId: id, name: id, setName: null, setId: null, number: null, rarity: null, productType: null, kind: "single", imageUrl: null, tcgplayerId: null, tcgplayerUrl: null },
  printing: null,
  market: 10,
  priceUpdatedAt: null,
  releaseDate,
});

const theme = (id: string, dates: (string | null)[], extra: Partial<Theme> = {}): Theme => ({
  id,
  title: id,
  blurb: "",
  look: "fan",
  hits: dates.map((d, i) => hit(`${id}-${i}`, d)),
  ...extra,
});

describe("pick-themes", () => {
  it("draws the same with the same seed", () => {
    const a = seededRandom(7);
    const b = seededRandom(7);
    expect([a(), a(), a()]).toEqual([b(), b(), b()]);
  });

  it("picks a daily theme and up to count others, never repeating", () => {
    const all = Array.from({ length: 20 }, (_, i) => theme(`t${i}`, ["2020-01-01", "2020-01-01", "2020-01-01"]));
    const pick = pickThemes(all, { day: 100, seed: 5, recent: new Set(), count: 14 });
    expect(pick.daily).not.toBeNull();
    expect(pick.shown).toHaveLength(14);
    const ids = [pick.daily!.id, ...pick.shown.map((t) => t.id)];
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("skips themes with fewer than three cards", () => {
    const pick = pickThemes([theme("small", ["2020-01-01"])], { day: 1, seed: 1, recent: new Set() });
    expect(pick.daily).toBeNull();
    expect(pick.shown).toEqual([]);
  });

  it("cuts collections to an era and keeps those with four or more", () => {
    const vintage = ["1999-01-09", "1999-06-16", "2000-01-01", "2003-01-01"];
    const all = [theme("v", [...vintage, "2020-01-01"]), theme("m", ["2020-01-01", "2021-01-01", "1999-01-09"])];
    const pick = pickThemes(all, { day: 1, seed: 1, recent: new Set() });
    const out = filteredThemes(pick, all, "vintage");
    expect(out.map((t) => t.id)).toEqual(["v"]);
    expect(out[0].hits).toHaveLength(4);
  });

  it("matches the app's era cut-offs", () => {
    expect(fitsFilter("vintage", { releaseDate: "2007-04-30" })).toBe(true);
    expect(fitsFilter("midEra", { releaseDate: "2007-05-01" })).toBe(true);
    expect(fitsFilter("modern", { releaseDate: "2017-02-01" })).toBe(true);
    expect(fitsFilter("modern", { releaseDate: null })).toBe(false);
    expect(fitsFilter("all", { releaseDate: null })).toBe(true);
  });

  it("keeps each product once", () => {
    expect(uniqueHits([hit("a", null), hit("b", null), hit("a", null)]).map((h) => h.product.id)).toEqual(["a", "b"]);
  });
});
