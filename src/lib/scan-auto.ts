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
  settle: 5,
  /** Mean change per pixel (0–255) between frames that still counts as holding still. */
  still: 7,
  /** Mean change in the coarse view since the last photo that counts as a new card (jitter stays well under it). */
  change: 22,
  /** Block size for that coarse view. */
  block: 8,
  /** Mean edge strength below this is too blurry (or too dark) to read. */
  sharp: 3.5,
  /** An edge line must be this many times the typical column (or row) to count as a border. */
  peak: 2,
  /** Card width over height, as seen in the guide; slabs are narrower, so the range is wide. */
  aspect: [0.5, 0.95] as const,
  /** The rectangle must cover at least this much of the guide's height. */
  minSpan: 0.5,
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

function median(xs: number[]) {
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.floor(s.length / 2)] || 1;
}

/** Index of the strongest value in [from, to). */
function argmax(xs: number[], from: number, to: number) {
  let best = from;
  for (let i = from; i < to; i++) if (xs[i] > xs[best]) best = i;
  return best;
}

/** Whether a card-shaped rectangle fills the guide. */
export function findCard(f: GrayFrame): { found: boolean; aspect: number | null } {
  const cols = new Array<number>(f.w).fill(0);
  const rows = new Array<number>(f.h).fill(0);
  for (let y = 1; y < f.h - 1; y++) {
    for (let x = 1; x < f.w - 1; x++) {
      cols[x] += Math.abs(at(f, x + 1, y) - at(f, x - 1, y));
      rows[y] += Math.abs(at(f, x, y + 1) - at(f, x, y - 1));
    }
  }
  // Borders sit in the outer 40% on each side.
  const l = argmax(cols, 1, Math.round(f.w * 0.4));
  const r = argmax(cols, Math.round(f.w * 0.6), f.w - 1);
  const t = argmax(rows, 1, Math.round(f.h * 0.4));
  const b = argmax(rows, Math.round(f.h * 0.6), f.h - 1);
  const mc = median(cols.slice(1, -1));
  const mr = median(rows.slice(1, -1));
  const edges = Math.min(cols[l], cols[r]) / mc >= AUTO.peak && Math.min(rows[t], rows[b]) / mr >= AUTO.peak;
  const aspect = b > t ? (r - l) / (b - t) : null;
  const shaped = aspect !== null && aspect >= AUTO.aspect[0] && aspect <= AUTO.aspect[1] && (b - t) / f.h >= AUTO.minSpan;
  return { found: edges && shaped, aspect };
}

/** One sampled frame in, and whether to take the photo now. `progress` (0–1) drives the lock-on ring. */
export function autoStep(state: AutoState, frame: GrayFrame, now: number): { state: AutoState; fire: boolean; progress: number; hint: AutoHint } {
  const moved = state.prev ? meanDiff(state.prev, frame) : 255;
  const card = findCard(frame).found;
  const next: AutoState = { ...state, prev: frame };

  // Just photographed: wait for the view to move on.
  if (state.shot) {
    // Only a real change in view re-arms it: the detector briefly losing the card must not.
    const movedOn = meanDiff(state.shot, coarse(frame)) >= AUTO.change;
    if (!movedOn || now - state.lastShotAt < AUTO.cooldownMs) return { state: { ...next, streak: 0 }, fire: false, progress: 0, hint: "next" };
    next.shot = null;
  }

  if (!card) return { state: { ...next, streak: 0 }, fire: false, progress: 0, hint: "searching" };
  if (sharpness(frame) < AUTO.sharp) return { state: { ...next, streak: 0 }, fire: false, progress: 0, hint: "blurry" };
  if (moved > AUTO.still) return { state: { ...next, streak: 0 }, fire: false, progress: 0, hint: "steady" };

  const streak = state.streak + 1;
  if (streak >= AUTO.settle) return { state: { ...next, streak: 0, shot: coarse(frame), lastShotAt: now }, fire: true, progress: 1, hint: "next" };
  return { state: { ...next, streak }, fire: false, progress: streak / AUTO.settle, hint: "steady" };
}
