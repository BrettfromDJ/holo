import { describe, expect, it } from "vitest";
import { artistSetKey, numberKey } from "./artists";

describe("artist matching", () => {
  it("matches set names across sources", () => {
    expect(artistSetKey("XY - BREAKthrough")).toBe(artistSetKey("BREAKthrough"));
    expect(artistSetKey("SWSH07: Evolving Skies")).toBe(artistSetKey("Evolving Skies"));
    expect(artistSetKey("Base Set (Shadowless)")).toBe(artistSetKey("Base"));
    expect(artistSetKey("Base Set 1st Edition")).toBe(artistSetKey("Base"));
  });
  it("matches card numbers", () => {
    expect(numberKey("118/162")).toBe("118");
    expect(numberKey("004/102")).toBe("4");
    expect(numberKey("TG05/TG30")).toBe("tg5");
    expect(numberKey("SWSH001")).toBe("swsh1");
    expect(numberKey("GG01")).toBe(numberKey("GG1"));
    expect(numberKey(null)).toBeNull();
  });
});
