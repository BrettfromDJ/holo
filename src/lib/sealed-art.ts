import manifest from "./sealed-art-manifest.json";

/**
 * Our own photos of sealed products (backgrounds removed), in `public/products/<dir>/<file>.webp`
 * and listed in `sealed-art-manifest.json` by set and product (made by `scripts/sealed-art.py`).
 *
 * The set: the one whose name (or another name it goes by) sits latest in the product's set name
 * ("Mega Evolution—Delta Reign" is Delta Reign, not Mega Evolution), else in the product's own name.
 * The product: its name without the set's names matched against the listed products (also
 * without their set's names and, as a second try, their bracketed notes): exactly, else the
 * longest listed name inside it ("Elite Trainer Box Case" is the case, not the box).
 * Same rules as the app's `SealedArt`, which is generated from the same list.
 */
type Entry = { set: string; aliases?: string[]; dir: string; products: Record<string, string> };

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

/** Where `needle` starts in `hay` as whole words, or -1. */
const at = (hay: string, needle: string) => (needle ? ` ${hay} `.indexOf(` ${needle} `) : -1);
const has = (hay: string, needle: string) => at(hay, needle) >= 0;

/** `s` without any of `names` (whole words). */
function without(s: string, names: string[]): string {
  let out = ` ${s} `;
  for (const n of names) if (n) out = out.split(` ${n} `).join(" ");
  return out.trim().replace(/\s+/g, " ");
}

const ENTRIES = (manifest as unknown as { sets: Entry[] }).sets.map((e) => {
  const names = [e.set, ...(e.aliases ?? [])].map(sealedWords).sort((a, b) => b.length - a.length);
  const strip = (k: string) => without(without(sealedWords(k), names), ["mega evolution", "pokemon"]);
  const keys = Object.keys(e.products).flatMap((k) => [
    { k, w: strip(k) },
    { k, w: strip(k.replace(/\([^)]*\)|\[[^\]]*\]/g, " ")) },
  ]).filter((x) => x.w);
  return { e, names, keys };
});

/** The set entry a product belongs to: the set name found latest in `hay`. */
function pickSet(hay: string) {
  let best: (typeof ENTRIES)[number] | null = null;
  let bestAt = -1;
  let bestLen = 0;
  for (const x of ENTRIES) {
    for (const n of x.names) {
      const i = at(hay, n);
      // Latest first; starting at the same place, the longer name.
      if (i >= 0 && (i > bestAt || (i === bestAt && n.length > bestLen))) {
        best = x;
        bestAt = i;
        bestLen = n.length;
      }
    }
  }
  return bestAt >= 0 ? best : null;
}

const cache = new Map<string, string | null>();

/** The path of our photo for a sealed product, or null. */
export function sealedArt(p: { name: string; setName?: string | null; kind?: string | null } | null | undefined): string | null {
  if (!p || p.kind === "single") return null;
  const id = `${p.name}|${p.setName ?? ""}`;
  if (cache.has(id)) return cache.get(id)!;
  const name = sealedWords(p.name);
  const set = pickSet(sealedWords(p.setName ?? "")) ?? pickSet(name);
  let found: string | null = null;
  if (set) {
    // The product part: its name without the set's names, the series or a code ("ME03", "SV08").
    const rest = without(name, [...set.names, "mega evolution", "pokemon"]).replace(/\b(me|sv|swsh)\d+[a-z]?\b/g, " ").trim().replace(/\s+/g, " ");
    const exact = set.keys.find((x) => x.w === rest);
    const inside = exact ?? set.keys.filter((x) => has(rest, x.w)).sort((a, b) => b.w.length - a.w.length)[0];
    if (inside) found = `/products/${set.e.dir}/${set.e.products[inside.k]}.webp`;
  }
  cache.set(id, found);
  return found;
}
