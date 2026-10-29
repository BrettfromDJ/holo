/**
 * Auto-capture for the scanner: decides, from small grayscale samples of the
 * card guide, when a card is in it, held still and in focus, and takes one
 * photo per card. It runs on the device and costs nothing; only the photos
 * it takes use scans.
 *
 * A card shows up as a rectangle: strong vertical edges near the left and
 * right of the guide and horizontal ones near the top and bottom, spaced
 * like a card (or a slab). After a photo it waits for the view to change
 * (the card is swapped or taken away) before it can take another, so a card
 * left on the table is never scanned twice.
 */

export interface GrayFrame {
  data: Uint8Array | Uint8ClampedArray;
  w: number;
  h: number;
}

export type AutoHint = "searching" | "steady" | "blurry" | "next";

export interface AutoState {
  prev: GrayFrame | null;
  /** A coarse copy of the frame last photographed; the view must move on from it before the next photo. */
  shot: GrayFrame | null;
  streak: number;
  lastShotAt: number;
}

export const AUTO_START: AutoState = { prev: null, shot: null, streak: 0, lastShotAt: -Infinity };

/** Tuning. Frames are sampled about 10 times a second. */
export const AUTO = {
  /** Good frames in a row before the photo (about half a second). */
  settle: 4,
  /** Mean change between frames (in the coarse view) that still counts as holding still; a hand always shakes a little. */
  still: 9,
  /** Mean change in the coarse view since the last photo that counts as a new card (jitter stays well under it). */
  change: 22,
  /** Block size for that coarse view. */
  block: 8,
  /** Mean edge strength below this is too blurry (or too dark) to read. */
  sharp: 2.5,
  /** Brightness step (0–255) between neighbouring pixels that counts as an edge. */
  edge: 14,
  /** Share of a border's length that must be a clear edge. */
  line: 0.35,
  /** Card width over height, as seen in the guide; slabs are narrower, so the range is wide. */
  aspect: [0.5, 0.95] as const,
  /** The rectangle must cover at least this much of the guide's height. */
  minSpan: 0.45,
  cooldownMs: 900,
};

const at = (f: GrayFrame, x: number, y: number) => f.data[y * f.w + x];

export function meanDiff(a: GrayFrame, b: GrayFrame): number {
  if (a.w !== b.w || a.h !== b.h) return 255;
  let s = 0;
  for (let i = 0; i < a.data.length; i++) s += Math.abs(a.data[i] - b.data[i]);
  return s / a.data.length;
}

/** Block averages: a blurred, tiny copy that shrugs off small shifts but not a swapped or removed card. */
export function coarse(f: GrayFrame, size = AUTO.block): GrayFrame {
  const w = Math.floor(f.w / size);
  const h = Math.floor(f.h / size);
  const data = new Uint8Array(w * h);
  for (let by = 0; by < h; by++) {
    for (let bx = 0; bx < w; bx++) {
      let s = 0;
      for (let y = by * size; y < (by + 1) * size; y++) for (let x = bx * size; x < (bx + 1) * size; x++) s += at(f, x, y);
      data[by * w + bx] = s / (size * size);
    }
  }
  return { data, w, h };
}

/** Mean absolute Laplacian: how much fine detail (focus) the frame has. */
export function sharpness(f: GrayFrame): number {
  let s = 0;
  let n = 0;
  for (let y = 1; y < f.h - 1; y++) {
    for (let x = 1; x < f.w - 1; x++) {
      s += Math.abs(4 * at(f, x, y) - at(f, x - 1, y) - at(f, x + 1, y) - at(f, x, y - 1) - at(f, x, y + 1));
      n++;
    }
  }
  return n ? s / n : 0;
}

/**
 * The outermost clear line scanning inward over [from, to) (or from `to` down
 * when `reverse`): the card's edge, not the busy art inside it. Falls back to
 * the strongest line, so the score still says how close it came.
 */
function border(frac: number[], from: number, to: number, reverse = false) {
  const idx = Array.from({ length: to - from }, (_, i) => (reverse ? to - 1 - i : from + i));
  const hit = idx.find((i) => frac[i] >= AUTO.line);
  if (hit !== undefined) return { at: hit, score: frac[hit] };
  const best = idx.reduce((a, i) => (frac[i] > frac[a] ? i : a), idx[0]);
  return { at: best, score: frac[best] ?? 0 };
}

export interface CardRead {
  found: boolean;
  aspect: number | null;
  /** How clearly each border shows (0–1): left, right, top, bottom. */
  borders: [number, number, number, number];
}

/**
 * Whether a card-shaped rectangle fills the guide. A border is a straight
 * line where most of its length is a clear light/dark edge; a nearby column
 * (or row) also counts, so a slightly tilted card still reads.
 */
export function findCard(f: GrayFrame): CardRead {
  const T = AUTO.edge;
  const R = 2;
  const y0 = Math.round(f.h * 0.15);
  const y1 = Math.round(f.h * 0.85);
  const x0 = Math.round(f.w * 0.15);
  const x1 = Math.round(f.w * 0.85);
  const colFrac = new Array<number>(f.w).fill(0);
  const rowFrac = new Array<number>(f.h).fill(0);
  for (let x = 1; x < f.w - 1; x++) {
    let hits = 0;
    for (let y = y0; y < y1; y++) {
      let hit = false;
      for (let dx = -R; dx <= R && !hit; dx++) {
        const xx = x + dx;
        if (xx >= 1 && xx < f.w - 1 && Math.abs(at(f, xx + 1, y) - at(f, xx - 1, y)) > T) hit = true;
      }
      if (hit) hits++;
    }
    colFrac[x] = hits / (y1 - y0);
  }
  for (let y = 1; y < f.h - 1; y++) {
    let hits = 0;
    for (let x = x0; x < x1; x++) {
      let hit = false;
      for (let dy = -R; dy <= R && !hit; dy++) {
        const yy = y + dy;
        if (yy >= 1 && yy < f.h - 1 && Math.abs(at(f, x, yy + 1) - at(f, x, yy - 1)) > T) hit = true;
      }
      if (hit) hits++;
    }
    rowFrac[y] = hits / (x1 - x0);
  }
  // Borders sit in the outer 45% on each side.
  const l = border(colFrac, 1, Math.round(f.w * 0.45));
  const r = border(colFrac, Math.round(f.w * 0.55), f.w - 1, true);
  const t = border(rowFrac, 1, Math.round(f.h * 0.45));
  const b = border(rowFrac, Math.round(f.h * 0.55), f.h - 1, true);
  const borders: CardRead["borders"] = [l.score, r.score, t.score, b.score];
  const edges = borders.every((v) => v >= AUTO.line);
  const aspect = b.at > t.at ? (r.at - l.at) / (b.at - t.at) : null;
  const shaped = aspect !== null && aspect >= AUTO.aspect[0] && aspect <= AUTO.aspect[1] && (b.at - t.at) / f.h >= AUTO.minSpan;
  return { found: edges && shaped, aspect, borders };
}

export interface AutoDebug {
  borders: [number, number, number, number];
  aspect: number | null;
  motion: number;
  sharp: number;
}

/** One sampled frame in, and whether to take the photo now. `progress` (0–1) drives the lock-on ring. */
export function autoStep(state: AutoState, frame: GrayFrame, now: number): { state: AutoState; fire: boolean; progress: number; hint: AutoHint; debug: AutoDebug } {
  const view = coarse(frame, 4);
  const motion = state.prev ? meanDiff(state.prev, view) : 255;
  const read = findCard(frame);
  const sharp = sharpness(frame);
  const debug: AutoDebug = { borders: read.borders, aspect: read.aspect, motion, sharp };
  const next: AutoState = { ...state, prev: view };
  const out = (hint: AutoHint, progress = 0, patch: Partial<AutoState> = { streak: 0 }, fire = false) => ({ state: { ...next, ...patch }, fire, progress, hint, debug });

  // Just photographed: wait for the view to move on. Only a real change re-arms it, not the detector briefly losing the card.
  if (state.shot) {
    if (meanDiff(state.shot, coarse(frame)) < AUTO.change || now - state.lastShotAt < AUTO.cooldownMs) return out("next");
    next.shot = null;
  }

  if (!read.found) return out("searching");
  if (sharp < AUTO.sharp) return out("blurry");
  if (motion > AUTO.still) return out("steady");

  const streak = state.streak + 1;
  if (streak >= AUTO.settle) return out("next", 1, { streak: 0, shot: coarse(frame), lastShotAt: now }, true);
  return out("steady", streak / AUTO.settle, { streak });
}
