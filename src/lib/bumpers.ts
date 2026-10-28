/** Bumper guards: the colored frames collectors snap around slabs. */
export interface Bumper {
  id: string;
  name: string;
  kind: "glitter" | "solid";
  /** CSS background for the bumper. */
  background: string;
}

const solid = (id: string, name: string, color: string): Bumper => ({
  id,
  name,
  kind: "solid",
  // A soft top-lit gradient so it reads as molded plastic, not a flat color.
  background: `linear-gradient(160deg, color-mix(in srgb, ${color} 82%, white), ${color} 45%, color-mix(in srgb, ${color} 80%, black))`,
});

const glitter = (id: string, name: string, stops: string): Bumper => ({ id, name, kind: "glitter", background: `linear-gradient(180deg, ${stops})` });

export const BUMPERS: Bumper[] = [
  glitter("rainbow", "Rainbow glitter", "#b56cf0, #f06cc4 35%, #ff5f6d 70%, #ff8a3d"),
  glitter("aurora", "Aurora glitter", "#7b5cff, #3fa9ff 40%, #2ed3a1 75%, #b6f05a"),
  glitter("sunset", "Sunset glitter", "#ff6a88, #ff8a3d 50%, #ffd23f"),
  glitter("ocean", "Ocean glitter", "#2c5cff, #23b5ff 55%, #5ef0e0"),
  glitter("cotton-candy", "Cotton candy glitter", "#ff9ad5, #c9a6ff 50%, #8fd3ff"),
  glitter("galaxy", "Galaxy glitter", "#1b1446, #4b2a8f 50%, #c04fd1"),
  solid("red", "Red", "#e5302f"),
  solid("orange", "Orange", "#ff7a1a"),
  solid("yellow", "Yellow", "#ffd21f"),
  solid("green", "Green", "#2cc84d"),
  solid("mint", "Mint", "#4fe0b0"),
  solid("blue", "Blue", "#36a6f0"),
  solid("navy", "Navy", "#1f2f9e"),
  solid("purple", "Purple", "#9a4be0"),
  solid("pink", "Pink", "#f05bbd"),
  solid("black", "Black", "#1c1c1e"),
  solid("white", "White", "#f4f4f6"),
];

export function bumperById(id: string | null | undefined): Bumper | null {
  return (id && BUMPERS.find((b) => b.id === id)) || null;
}

/** Sparse bright specks laid over glitter bumpers. */
export const GLITTER_SPECKS =
  "url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='90' height='90'><filter id='s'><feTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='1' seed='4' stitchTiles='stitch'/><feColorMatrix values='0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  10 0 0 0 -6.6'/></filter><rect width='100%' height='100%' filter='url(%23s)'/></svg>\")";
