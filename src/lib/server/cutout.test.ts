import { describe, expect, it } from "vitest";
import { cutoutWhiteBackground } from "./cutout";

/** 20×20 image: white backdrop, a dark box in the middle with a white logo inside it. */
function productOnWhite() {
  const w = 20;
  const h = 20;
  const d = new Uint8ClampedArray(w * h * 4).fill(255);
  for (let y = 5; y < 15; y++) {
    for (let x = 5; x < 15; x++) {
      const i = (y * w + x) * 4;
      const logo = x >= 9 && x <= 10 && y >= 9 && y <= 10;
      d[i] = d[i + 1] = d[i + 2] = logo ? 255 : 40;
    }
  }
  return { d, w, h };
}

const alphaAt = (data: Uint8ClampedArray, w: number, x: number, y: number) => data[(y * w + x) * 4 + 3];

describe("cutoutWhiteBackground", () => {
  it("clears the border-connected white but keeps white inside the product", () => {
    const { d, w, h } = productOnWhite();
    const res = cutoutWhiteBackground(d, w, h)!;
    expect(res).not.toBeNull();
    expect(alphaAt(res.data, w, 0, 0)).toBe(0);
    expect(alphaAt(res.data, w, 2, 12)).toBe(0);
    expect(alphaAt(res.data, w, 9, 9)).toBe(255); // the white logo
    expect(alphaAt(res.data, w, 7, 7)).toBe(255); // the dark box
    expect(res.removed).toBeCloseTo(0.75, 2);
  });

  it("leaves photos that aren't on white alone", () => {
    const w = 10;
    const h = 10;
    const d = new Uint8ClampedArray(w * h * 4);
    for (let i = 0; i < d.length; i += 4) {
      d[i] = 120;
      d[i + 1] = 90;
      d[i + 2] = 60;
      d[i + 3] = 255;
    }
    expect(cutoutWhiteBackground(d, w, h)).toBeNull();
  });

  it("leaves an all-white image alone", () => {
    const d = new Uint8ClampedArray(10 * 10 * 4).fill(255);
    expect(cutoutWhiteBackground(d, 10, 10)).toBeNull();
  });
});
