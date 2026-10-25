/**
 * Makes the plain white backdrop of a product photo transparent.
 *
 * Only near-white pixels connected to the image border are removed (a flood
 * fill from the edges), so white printing on the product itself survives.
 * Pixels on the boundary get partial alpha and are "un-blended" from white,
 * which avoids a light halo on dark backgrounds.
 *
 * Returns null when the photo doesn't look like a product on white — the
 * caller then serves the original untouched.
 */
export interface CutoutResult {
  data: Uint8ClampedArray;
  /** Share of pixels made fully transparent. */
  removed: number;
}

/** Channel value at or above which a low-saturation pixel counts as backdrop. */
const WHITE = 236;
/** Max channel spread for a pixel to count as neutral (not a pale colour). */
const NEUTRAL = 18;

function isBackdrop(d: ArrayLike<number>, i: number): boolean {
  const r = d[i];
  const g = d[i + 1];
  const b = d[i + 2];
  const min = Math.min(r, g, b);
  return min >= WHITE && Math.max(r, g, b) - min <= NEUTRAL && d[i + 3] > 0;
}

export function cutoutWhiteBackground(rgba: ArrayLike<number>, width: number, height: number): CutoutResult | null {
  const n = width * height;
  if (!n) return null;

  // 1. Is this a photo on white at all? Most of the border must be backdrop.
  let border = 0;
  let borderWhite = 0;
  const checkBorder = (x: number, y: number) => {
    border++;
    if (isBackdrop(rgba, (y * width + x) * 4)) borderWhite++;
  };
  for (let x = 0; x < width; x++) {
    checkBorder(x, 0);
    checkBorder(x, height - 1);
  }
  for (let y = 1; y < height - 1; y++) {
    checkBorder(0, y);
    checkBorder(width - 1, y);
  }
  if (borderWhite / border < 0.6) return null;

  // 2. Flood-fill backdrop pixels reachable from the border.
  const bg = new Uint8Array(n);
  const queue = new Int32Array(n);
  let head = 0;
  let tail = 0;
  const push = (p: number) => {
    if (bg[p] || !isBackdrop(rgba, p * 4)) return;
    bg[p] = 1;
    queue[tail++] = p;
  };
  for (let x = 0; x < width; x++) {
    push(x);
    push((height - 1) * width + x);
  }
  for (let y = 0; y < height; y++) {
    push(y * width);
    push(y * width + width - 1);
  }
  while (head < tail) {
    const p = queue[head++];
    const x = p % width;
    if (x > 0) push(p - 1);
    if (x < width - 1) push(p + 1);
    if (p >= width) push(p - width);
    if (p < n - width) push(p + width);
  }

  const removed = tail / n;
  // Nothing removed, or nearly everything (a white product filling the frame): leave it.
  if (removed < 0.03 || removed > 0.92) return null;

  // 3. Write alpha. Backdrop → transparent; pixels touching the backdrop get
  //    alpha from how far they are from white, with white blended back out.
  const out = new Uint8ClampedArray(n * 4);
  for (let p = 0; p < n; p++) {
    const i = p * 4;
    out[i] = rgba[i];
    out[i + 1] = rgba[i + 1];
    out[i + 2] = rgba[i + 2];
    out[i + 3] = rgba[i + 3];
    if (bg[p]) {
      out[i + 3] = 0;
      continue;
    }
    const x = p % width;
    const edge = (x > 0 && bg[p - 1]) || (x < width - 1 && bg[p + 1]) || (p >= width && bg[p - width]) || (p < n - width && bg[p + width]);
    if (!edge) continue;
    const min = Math.min(rgba[i], rgba[i + 1], rgba[i + 2]);
    const a = Math.min(1, (255 - min) / (255 - WHITE + 24));
    if (a >= 1) continue;
    const alpha = Math.max(0.15, a);
    for (let c = 0; c < 3; c++) out[i + c] = (rgba[i + c] - 255 * (1 - alpha)) / alpha;
    out[i + 3] = Math.round(rgba[i + 3] * alpha);
  }
  return { data: out, removed };
}
