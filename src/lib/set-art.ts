import manifest from "./set-art-manifest.json";
import manifestJa from "./set-art-manifest-ja.json";

/**
 * Our own artwork for Pokémon sets, English and Japanese (a wide background, the set's logo, and
 * its symbol), in public/sets/pokemon/<slug>/ and public/sets/pokemon-japan/<slug>/. English sets
 * are matched by name; Japanese ones by the set code the catalog writes before the name
 * ("M2a: MEGA Dream ex") first, then by name. Matched to catalog sets by name, since the catalog writes names
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
export function setNameKey(name: string, japanese = false): string {
  let s = name.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  s = s.replace(/^(sv|swsh|sm|xy|bw|me|dp|hgss)[0-9.]*\s*:\s*/, "").replace(/^(sm|xy|bw|dp|hgss|swsh|sv|me)\s+-\s+/, "");
  // Japanese names lead with their own code ("S12a: ", "SM10b: ", "M2a: ").
  if (japanese) s = s.replace(/^[a-z0-9+-]*[0-9][a-z0-9+-]*\s*:\s*/, "");
  s = s.replace(/&/g, " and ").replace(/['’]/g, "").replace(/[^a-z0-9]+/g, " ");
  const drop = ["and", "the", "set", "cards", "card", "pokemon", ...(japanese ? ["japanese"] : [])];
  const words = s.split(" ").filter((w) => w && !drop.includes(w));
  let joined = words.join(" ").replace(/\bpromos\b/g, "promo").replace(/\bblack star\b/g, "").replace(/\s+/g, " ").trim();
  joined = joined.replace(/ base$/, "");
  // "MEGA Dream ex", "Shiny Treasure ex": the ex is part of the box name only.
  if (japanese) joined = joined.replace(/ ex$/, "");
  return joined.replace(/ /g, "");
}

/** The set code a Japanese catalog name starts with ("M2a: MEGA Dream ex" → "m2a"). */
function leadingCode(name: string): string | null {
  const m = name.match(/^\s*([A-Za-z0-9+-]*[0-9][A-Za-z0-9+-]*)\s*:/);
  return m ? m[1].toLowerCase() : null;
}

interface Index {
  dir: string;
  japanese: boolean;
  byKey: Map<string, Entry>;
  byLoose: Map<string, Entry[]>;
  byCode: Map<string, Entry[]>;
}

function index(entries: Entry[], dir: string, japanese: boolean): Index {
  const ix: Index = { dir, japanese, byKey: new Map(), byLoose: new Map(), byCode: new Map() };
  for (const e of entries) {
    for (const n of [e.name, ...(ALIASES[e.name] ?? [])]) {
      const k = setNameKey(n, japanese);
      if (!ix.byKey.has(k)) ix.byKey.set(k, e);
      const loose = k.replace(/promo$/, "");
      ix.byLoose.set(loose, [...(ix.byLoose.get(loose) ?? []), e]);
    }
    if (e.code) {
      const c = e.code.toLowerCase();
      ix.byCode.set(c, [...(ix.byCode.get(c) ?? []), e]);
    }
  }
  return ix;
}

const ENGLISH = index(manifest as Entry[], "pokemon", false);
const JAPANESE = index(manifestJa as Entry[], "pokemon-japan", true);

function paths(ix: Index, e: Entry): SetArtwork {
  const base = `/sets/${ix.dir}/${e.slug}`;
  return { background: `${base}/background.webp`, logo: `${base}/logo.webp`, symbol: e.symbol ? `${base}/symbol.webp` : null };
}

/** Our artwork for a set, or null. Only Pokémon sets (English and Japanese) have any. */
export function setArtFor(set: { gameName: string | null | undefined; name: string; abbreviation?: string | null }): SetArtwork | null {
  const game = (set.gameName ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim();
  const ix = game === "pokemon" ? ENGLISH : /^pokemon japan(ese)?$/.test(game) ? JAPANESE : null;
  if (!ix) return null;
  const k = setNameKey(set.name, ix.japanese);
  // Japanese: the set's code, when exactly one of our sets has it and the names agree or there's
  // no better name match. Codes like "Pt" or "DP4" cover several decks, so those fall to names.
  if (ix.japanese) {
    for (const code of [leadingCode(set.name), set.abbreviation?.toLowerCase() ?? null]) {
      const hits = code ? ix.byCode.get(code) : undefined;
      if (hits?.length === 1) return paths(ix, hits[0]);
      const named = hits?.find((e) => setNameKey(e.name, true) === k);
      if (named) return paths(ix, named);
    }
  }
  const hit = ix.byKey.get(k);
  if (hit) return paths(ix, hit);
  // "…Promos" written with or without the word: only when that leaves exactly one set.
  const loose = ix.byLoose.get(k.replace(/promo$/, ""));
  return loose?.length === 1 ? paths(ix, loose[0]) : null;
}
