import { describe, expect, it } from "vitest";
import { AUTO, AUTO_START, autoStep, findCard, type AutoState, type GrayFrame } from "./scan-auto";

const W = 76;
const H = 106;

/** A flat table, optionally with a card (bright border, detailed art) on it. */
function frame(card: { x: number; y: number; w: number; h: number; seed?: number } | null, shift = 0): GrayFrame {
  const data = new Uint8Array(W * H).fill(60);
  if (card) {
    for (let y = card.y; y < card.y + card.h; y++) {
      for (let x = card.x; x < card.x + card.w; x++) {
        const inner = x > card.x + 3 && x < card.x + card.w - 4 && y > card.y + 3 && y < card.y + card.h - 4;
        // Fine detail inside so it reads as sharp; a different seed is a different card.
        data[y * W + x] = inner ? 120 + (((x + shift) * 7 + y * 13 + (card.seed ?? 0) * 31) % 5) * 22 : 230;
      }
    }
  }
  return { data, w: W, h: H };
}

const card = { x: 8, y: 10, w: 60, h: 86 };

function run(frames: GrayFrame[], start: AutoState = AUTO_START, t0 = 0) {
  let state = start;
  const fired: number[] = [];
  frames.forEach((f, i) => {
    const r = autoStep(state, f, t0 + i * 100);
    state = r.state;
    if (r.fire) fired.push(i);
  });
  return { state, fired };
}

describe("scan auto-capture", () => {
  it("finds a card-shaped rectangle, not an empty table or a wide box", () => {
    expect(findCard(frame(card)).found).toBe(true);
    expect(findCard(frame(null)).found).toBe(false);
    expect(findCard(frame({ x: 4, y: 30, w: 68, h: 40 })).found).toBe(false);
  });

  it("ignores floor tiles, planks and other rectangles that aren't busy inside", () => {
    // Tile grout: a card-sized rectangle of lines on a plain floor.
    const tiles = frame(null);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if ([8, 9, 67, 68].includes(x) || [10, 11, 95, 96].includes(y)) tiles.data[y * W + x] = 200;
    expect(findCard(tiles).found).toBe(false);
    // Wood grain everywhere, with plank seams in the same place.
    const wood = frame(null);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) wood.data[y * W + x] = [8, 67].includes(x) || [10, 96].includes(y) ? 20 : 70 + ((x * 3 + Math.floor(y / 2) * 5) % 4) * 9;
    expect(findCard(wood).found).toBe(false);
  });

  it("takes one photo once the card has been still for a moment", () => {
    const { fired } = run(Array.from({ length: 12 }, () => frame(card)));
    expect(fired).toEqual([AUTO.settle]);
  });

  it("waits while the card is moving", () => {
    const { fired } = run(Array.from({ length: 10 }, (_, i) => frame({ ...card, x: 4 + (i % 3) * 4 })));
    expect(fired).toEqual([]);
  });

  it("never scans the same card twice, and takes the next one after a swap", () => {
    const first = Array.from({ length: 30 }, () => frame(card));
    // A swap passes through a moment without the card (the hand lifts it away).
    const between = Array.from({ length: 2 }, () => frame(null));
    const swap = Array.from({ length: 15 }, () => frame({ ...card, seed: 3 }));
    const { fired } = run([...first, ...between, ...swap]);
    expect(fired.length).toBe(2);
    expect(fired[1]).toBeGreaterThan(30);
  });

  it("doesn't re-scan a card that jitters in the hand", () => {
    const { fired } = run(Array.from({ length: 40 }, (_, i) => frame({ ...card, x: card.x + (i % 4) }, i % 3)));
    expect(fired.length).toBeLessThanOrEqual(1);
  });

  it("works with a real camera: sensor noise, a soft image and a hand that shakes a pixel", () => {
    let seed = 7;
    const rand = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
    const real = (i: number): GrayFrame => {
      const f = frame({ ...card, x: card.x + (i % 2), y: card.y + ((i >> 1) % 2) });
      const out = new Uint8Array(f.data.length);
      for (let y = 0; y < H; y++)
        for (let x = 0; x < W; x++) {
          // 3x3 blur plus noise.
          let s = 0;
          for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) s += f.data[Math.min(H - 1, Math.max(0, y + dy)) * W + Math.min(W - 1, Math.max(0, x + dx))];
          out[y * W + x] = Math.max(0, Math.min(255, s / 9 + (rand() - 0.5) * 14));
        }
      return { data: out, w: W, h: H };
    };
    const { fired } = run(Array.from({ length: 30 }, (_, i) => real(i)));
    expect(fired.length).toBe(1);
  });

  it("takes a card that fills the guide, held by fingers, slightly tilted", () => {
    const f = frame({ x: 5, y: 6, w: 66, h: 94 });
    // Tilt: the card's right edge drifts 3px over its height.
    for (let y = 6; y < 100; y++) for (let x = 71; x < 71 + Math.floor(((y - 6) / 94) * 3); x++) f.data[y * W + x] = 230;
    // Fingers along the sides: blobs of skin with shading in the margin.
    for (let y = 30; y < 80; y++) for (let x = 0; x < 6; x++) f.data[y * W + x] = 150 + ((x * 11 + y * 7) % 5) * 12;
    for (let y = 40; y < 90; y++) for (let x = 73; x < W; x++) f.data[y * W + x] = 150 + ((x * 13 + y * 5) % 5) * 12;
    expect(findCard(f).found).toBe(true);
  });

  it("re-arms after the card is taken away", () => {
    const { fired } = run([...Array.from({ length: 12 }, () => frame(card)), ...Array.from({ length: 5 }, () => frame(null)), ...Array.from({ length: 10 }, () => frame(card))]);
    expect(fired.length).toBe(2);
  });
});
