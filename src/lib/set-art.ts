import manifest from "./set-art-manifest.json";

/**
 * Our own artwork for English Pokémon sets (a wide background, the set's logo, and its symbol),
 * in public/sets/pokemon/<slug>/. Matched to catalog sets by name, since the catalog writes names
 * its own way ("SWSH12.5: Crown Zenith", "SM - Guardians Rising", "XY Base Set"). TCG API's own
 * art stays the fallback for every set without a match.
 */
export interface SetArtwork {
  background: string;
  logo: string;
  symbol: string | null;
}

interface Entry {
  slug: string;
  name: string;
  code: string | null;
  symbol: boolean;
}

/** Folder names the catalog spells differently enough that the rules below don't reach. */
const ALIASES: Record<string, string[]> = {
  "Base Set Unlimited": ["Base Set"],
  "Sun & Moon": ["SM Base Set"],
  "Sun & Moon Black Star Promo": ["SM Promos"],
  "Pokemon Card 151": ["Scarlet & Violet 151"],
  "Mcdonald's 25th Anniversary": ["McDonald's 25th Anniversary Promos"],
  "Mcdonald's Dragon Discovery": ["McDonald's Dragon Discovery Promos"],
};

/** A name reduced to what matters: no series prefix, case, accents, punctuation, "&"/"and", "set". */
export function setNameKey(name: string): string {
  let s = name.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  s = s.replace(/^(sv|swsh|sm|xy|bw|me|dp|hgss)[0-9.]*\s*:\s*/, "").replace(/^(sm|xy|bw|dp|hgss|swsh|sv|me)\s+-\s+/, "");
  s = s.replace(/&/g, " and ").replace(/['’]/g, "").replace(/[^a-z0-9]+/g, " ");
  const words = s.split(" ").filter((w) => w && !["and", "the", "set", "cards", "card", "pokemon"].includes(w));
  let joined = words.join(" ").replace(/\bpromos\b/g, "promo").replace(/\bblack star\b/g, "").replace(/\s+/g, " ").trim();
  joined = joined.replace(/ base$/, "");
  return joined.replace(/ /g, "");
}

const BY_KEY = new Map<string, Entry>();
const BY_KEY_NO_PROMO = new Map<string, Entry[]>();
for (const e of manifest as Entry[]) {
  for (const n of [e.name, ...(ALIASES[e.name] ?? [])]) {
    const k = setNameKey(n);
    if (!BY_KEY.has(k)) BY_KEY.set(k, e);
    const loose = k.replace(/promo$/, "");
    BY_KEY_NO_PROMO.set(loose, [...(BY_KEY_NO_PROMO.get(loose) ?? []), e]);
  }
}

function paths(e: Entry): SetArtwork {
  const base = `/sets/pokemon/${e.slug}`;
  return { background: `${base}/background.webp`, logo: `${base}/logo.webp`, symbol: e.symbol ? `${base}/symbol.webp` : null };
}

/** Our artwork for a set, or null. Only English Pokémon sets have any. */
export function setArtFor(set: { gameName: string | null | undefined; name: string }): SetArtwork | null {
  const game = (set.gameName ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
  if (game !== "pokemon") return null;
  const k = setNameKey(set.name);
  const hit = BY_KEY.get(k);
  if (hit) return paths(hit);
  // "…Promos" written with or without the word: only when that leaves exactly one set.
  const loose = BY_KEY_NO_PROMO.get(k.replace(/promo$/, ""));
  return loose?.length === 1 ? paths(loose[0]) : null;
}
