import { describe, expect, it } from "vitest";
import { parseNumberToken } from "./search-match";
import { SET_CODES, pickSetCode } from "./set-codes";

const isNumber = (w: string) => parseNumberToken(w) !== null;
const pick = (raw: string) => pickSetCode(raw, raw.toLowerCase().split(" "), isNumber);

describe("pickSetCode", () => {
  it("finds a code before a number", () => {
    expect(pick("obf 223")).toEqual({ code: "obf", words: ["223"] });
    expect(pick("CRZ GG05")).toEqual({ code: "crz", words: ["gg05"] });
    expect(SET_CODES.obf).toBe("obsidian flames");
  });
  it("reads 151 as the set only before another number", () => {
    expect(pick("151 199")).toEqual({ code: "151", words: ["199"] });
    expect(pick("charizard 151")).toBeNull();
    expect(pick("151")).toBeNull();
  });
  it("takes a code alone only in capitals", () => {
    expect(pick("CRZ")).toEqual({ code: "crz", words: [] });
    expect(pick("pre")).toBeNull();
    expect(pick("umbreon")).toBeNull();
  });
});
