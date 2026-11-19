import { describe, expect, it } from "vitest";
import { summarizeEras, WEEK_MIN_CARDS, type EraRow } from "./era-summary";

const row = (id: string, market: number, change24h: number | null, change7d: number | null, releaseDate: string): EraRow => ({ id, market, change24h, change7d, releaseDate });

describe("era summaries", () => {
  it("uses today's change until enough cards have a week, and counts up, down and flat", () => {
    const rows = [row("a", 50, 3, null, "1999-01-09"), row("b", 30, -2, null, "2000-12-16"), row("c", 10, 0.1, null, "2001-06-01")];
    const vintage = summarizeEras(rows).find((e) => e.era === "vintage")!;
    expect(vintage.window).toBe("24h");
    expect(vintage.median).toBe(0.1);
    expect([vintage.up, vintage.down, vintage.flat, vintage.tracked]).toEqual([1, 1, 1, 3]);
    // Biggest moves from $20, biggest first either way.
    expect(vintage.moveIds.map((m) => m.id)).toEqual(["a", "b"]);
  });

  it("switches to the week once enough cards have one", () => {
    const rows = Array.from({ length: WEEK_MIN_CARDS }, (_, i) => row(`m${i}`, 25, 1, 5, "2023-09-22"));
    const modern = summarizeEras(rows).find((e) => e.era === "modern")!;
    expect(modern.window).toBe("7d");
    expect(modern.median).toBe(5);
  });

  it("an era with no cards is empty, not missing", () => {
    const mid = summarizeEras([]).find((e) => e.era === "midEra")!;
    expect(mid.tracked).toBe(0);
    expect(mid.moveIds).toEqual([]);
  });
});
