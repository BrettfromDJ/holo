import manifest from "./sealed-art-manifest.json";

/**
 * Our own photos of sealed products (backgrounds removed), in `public/products/<dir>/<file>.webp`
 * and listed in `sealed-art-manifest.json` by set and product. A product gets one when its set
 * (or its name) names the set and its name, without the set's name, matches a listed product:
 * exactly, else the longest listed name inside it ("Delta Reign Elite Trainer Box Case" is the
 * case, not the box). Same rules as the app's `SealedArt`, which keeps the same list.
 */
type Entry = { set: string; dir: string; products: Record<string, string> };

/** Lowercase words only: "Build & Battle Box" → "build and battle box". */
export function sealedWords(s: string): string {
  return s
    .toLowerCase()
    .replace(/é/g, "e")
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ");
}

const has = (hay: string, needle: string) => ` ${hay} `.includes(` ${needle} `);

/** The path of our photo for a sealed product, or null. */
export function sealedArt(p: { name: string; setName?: string | null; kind?: string | null } | null | undefined): string | null {
  if (!p || p.kind === "single") return null;
  const name = sealedWords(p.name);
  const setName = sealedWords(p.setName ?? "");
  for (const entry of (manifest as { sets: Entry[] }).sets) {
    const set = sealedWords(entry.set);
    if (!has(setName, set) && !has(name, set)) continue;
    // The product part: the name without the set's name, the series ("Mega Evolution") or a code ("ME03").
    const rest = ` ${name} `.replace(` ${set} `, " ").replace(" mega evolution ", " ").replace(/ me\d+[a-z]? /g, " ").trim();
    // Each listed name, and the same without its bracketed notes ("Pokemon Center Elite Trainer
    // Box (Exclusive)" also answers to "Pokemon Center Elite Trainer Box").
    const keys = Object.keys(entry.products).flatMap((k) => [
      { k, w: sealedWords(k) },
      { k, w: sealedWords(k.replace(/\([^)]*\)|\[[^\]]*\]/g, " ")) },
    ]);
    const exact = keys.find((x) => x.w === rest);
    const inside = exact ?? keys.filter((x) => has(rest, x.w)).sort((a, b) => b.w.length - a.w.length)[0];
    if (inside) return `/products/${entry.dir}/${entry.products[inside.k]}.webp`;
  }
  return null;
}
