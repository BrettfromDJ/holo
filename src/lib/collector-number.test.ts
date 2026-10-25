import { describe, expect, it } from "vitest";
import { compareCollectorNumbers } from "./collector-number";

describe("compareCollectorNumbers", () => {
  it("sorts numerically, with prefixed and missing numbers handled", () => {
    const list = ["215/203", "4/102", "TG05", "10/102", null, "2/102", "TG10"];
    expect([...list].sort(compareCollectorNumbers)).toEqual(["2/102", "4/102", "10/102", "215/203", "TG05", "TG10", null]);
  });
});
