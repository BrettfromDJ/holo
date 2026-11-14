/**
 * Old English Pokémon sets that were printed twice, 1st Edition and Unlimited. The catalog
 * (TCGplayer, through TCG API) lists each as one set with both versions of every card; we show
 * them as two sets, "Base Set 1st Edition" and "Base Set Unlimited", each priced and tracked on
 * its own. The two halves share the catalog set's slug plus "--1st-edition" or "--unlimited".
 * Same as the app's `Editions`.
 */

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
