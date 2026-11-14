/**
 * Old English Pokémon sets that were printed twice, 1st Edition and Unlimited. The catalog
 * (TCGplayer, through TCG API) lists each as one set with both versions of every card; we show
 * them as two sets, "Base Set 1st Edition" and "Base Set Unlimited", each priced and tracked on
 * its own. The two halves share the catalog set's slug plus "--1st-edition" or "--unlimited".
 * Same as the app's `Editions`.
 */

import unlimitedArt from "./unlimited-art-manifest.json";

export type Edition = "1st-edition" | "unlimited";

const EDITION_SETS = new Set([
  "base set",
  "jungle",
  "fossil",
  "team rocket",
  "gym heroes",
  "gym challenge",
  "neo genesis",
  "neo discovery",
  "neo revelation",
  "neo destiny",
]);

function fold(s: string | null | undefined): string {
  return (s ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
}

/** An English Pokémon set printed in both editions. `gameName` is the catalog's ("Pokemon"); leave it out when only the set name is known. */
export function isEditionSet(set: { name: string | null | undefined; gameName?: string | null }): boolean {
  if (set.gameName !== undefined && fold(set.gameName) !== "pokemon") return false;
  return EDITION_SETS.has(fold(set.name));
}

export const EDITIONS: Edition[] = ["1st-edition", "unlimited"];

/** The slug of one half: "base-set--1st-edition". */
export function editionSlug(slug: string, edition: Edition): string {
  return `${slug}--${edition}`;
}

/** The catalog set and edition a half's slug names, or null for an ordinary slug. */
export function parseEditionSlug(slug: string): { slug: string; edition: Edition } | null {
  const m = slug.match(/^(.*)--(1st-edition|unlimited)$/);
  return m ? { slug: m[1], edition: m[2] as Edition } : null;
}

/** "Base Set 1st Edition", "Jungle Unlimited". */
export function editionName(name: string, edition: Edition): string {
  return `${name} ${edition === "1st-edition" ? "1st Edition" : "Unlimited"}`;
}

/** The name our own artwork goes by: the 1st Edition folders, and the plain set for Unlimited. */
export function editionArtName(name: string, edition: Edition): string {
  return edition === "1st-edition" ? `${name} 1st Edition` : name;
}

/** A printing that is the 1st Edition one ("1st Edition", "1st Edition Holofoil"). */
export function isFirstEditionPrinting(printing: string | null | undefined): boolean {
  return /1st\s*edition/i.test(printing ?? "");
}

/** Which half a copy belongs to, from its printing. */
export function editionOf(printing: string | null | undefined): Edition {
  return isFirstEditionPrinting(printing) ? "1st-edition" : "unlimited";
}

/**
 * Our own photos of the Unlimited prints (the catalog's pictures for these sets are the 1st
 * Edition scans, stamp and all): public/cards/pokemon/<dir>/<number>.webp, listed in
 * unlimited-art-manifest.json by set. Null for a card we have no photo of.
 */
export function unlimitedCardImage(setName: string | null | undefined, number: string | null | undefined): string | null {
  const entry = (unlimitedArt as Record<string, { dir: string; numbers: number[] }>)[fold(setName)];
  const n = Number(number?.match(/^\s*#?(\d+)/)?.[1]);
  return entry && n && entry.numbers.includes(n) ? `/cards/pokemon/${entry.dir}/${n}.webp` : null;
}

/**
 * Sets whose catalog pictures are the Unlimited prints (no stamp), so their 1st Edition half needs
 * other photos: pokemontcg.io's scans of these are the 1st Edition prints.
 */
const FIRST_EDITION_ART: Record<string, string> = { "base set": "base1" };

/** The 1st Edition print's photo for a card, when the catalog's own picture lacks the stamp. */
export function firstEditionCardImage(setName: string | null | undefined, number: string | null | undefined): string | null {
  const code = FIRST_EDITION_ART[fold(setName)];
  const n = Number(number?.match(/^\s*#?(\d+)/)?.[1]);
  return code && n ? `https://images.pokemontcg.io/${code}/${n}_hires.png` : null;
}

/** A card shown as one printing: the photo of that edition's print, where the catalog's is the other one. */
export function withEditionArt<P extends { kind?: string | null; source?: string | null; setName?: string | null; number?: string | null; imageUrl?: string | null }>(product: P, printing: string | null | undefined): P;
export function withEditionArt<P extends { kind?: string | null; source?: string | null; setName?: string | null; number?: string | null; imageUrl?: string | null }>(product: P | undefined, printing: string | null | undefined): P | undefined;
export function withEditionArt<P extends { kind?: string | null; source?: string | null; setName?: string | null; number?: string | null; imageUrl?: string | null }>(product: P | undefined, printing: string | null | undefined): P | undefined {
  // Only when the printing is known: no printing means we can't tell which edition it is.
  if (!product || !printing?.trim() || product.kind !== "single" || product.source !== "tcgapi") return product;
  const art = editionOf(printing) === "unlimited" ? unlimitedCardImage(product.setName, product.number) : firstEditionCardImage(product.setName, product.number);
  return art ? { ...product, imageUrl: art } : product;
}
