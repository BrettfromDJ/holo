/**
 * Set short-codes as collectors write them ("OBF 223", "CRZ GG05", "151 199"): the code printed
 * on modern cards (the Pokémon TCG Online / Live code), mapped to words that appear in the
 * catalog's set name. Codes the catalog itself knows (catalog_sets.abbreviation) are looked up
 * on the server too, so this list only needs the common ones.
 */
export const SET_CODES: Record<string, string> = {
  // Mega Evolution and Scarlet & Violet
  meg: "mega evolution",
  pfl: "phantasmal flames",
  blk: "black bolt",
  wht: "white flare",
  dri: "destined rivals",
  jtg: "journey together",
  pre: "prismatic evolutions",
  ssp: "surging sparks",
  scr: "stellar crown",
  sfa: "shrouded fable",
  twm: "twilight masquerade",
  tef: "temporal forces",
  paf: "paldean fates",
  par: "paradox rift",
  "151": "151",
  obf: "obsidian flames",
  pal: "paldea evolved",
  svi: "scarlet & violet base",
  svp: "scarlet & violet promo",
  // Sword & Shield
  crz: "crown zenith",
  sit: "silver tempest",
  lor: "lost origin",
  pgo: "pokemon go",
  asr: "astral radiance",
  brs: "brilliant stars",
  fst: "fusion strike",
  cel: "celebrations",
  evs: "evolving skies",
  cre: "chilling reign",
  bst: "battle styles",
  shf: "shining fates",
  viv: "vivid voltage",
  cpa: "champion's path",
  daa: "darkness ablaze",
  rcl: "rebel clash",
  ssh: "sword & shield base",
  // Sun & Moon and earlier
  cec: "cosmic eclipse",
  hif: "hidden fates",
  unm: "unified minds",
  unb: "unbroken bonds",
  teu: "team up",
  lot: "lost thunder",
  drm: "dragon majesty",
  ces: "celestial storm",
  fli: "forbidden light",
  upr: "ultra prism",
  bus: "burning shadows",
  sli: "shining legends",
  gri: "guardians rising",
  evo: "evolutions",
  gen: "generations",
};

/** A word that could be a set code: 2 to 5 letters or digits, at least one letter (or "151"). */
const CODE_SHAPE = /^(?=.*[a-z])[a-z0-9]{2,5}$|^151$/;

/**
 * Picks a set code out of the query's words. It only counts as a code when the query also has a
 * collector number ("obf 223") or it was typed in capitals ("CRZ"), so ordinary words typed in
 * passing ("pre…" on the way to "premium") still search names. "151" counts only before another
 * number ("151 199"). Returns the code and the other words, or null.
 */
export function pickSetCode(raw: string, words: string[], isNumber: (w: string) => boolean): { code: string; words: string[] } | null {
  const numbers = words.filter(isNumber);
  for (let i = 0; i < words.length; i++) {
    const w = words[i];
    if (!CODE_SHAPE.test(w)) continue;
    const typedInCaps = new RegExp(`(^|[^A-Za-z0-9])${w.toUpperCase()}([^A-Za-z0-9]|$)`).test(raw);
    if (w === "151") {
      if (numbers.filter((n) => n !== "151").length === 0 && numbers.length < 2) continue;
    } else if (isNumber(w)) {
      continue;
    } else if (!(numbers.length > 0 || typedInCaps)) {
      continue;
    }
    return { code: w, words: words.filter((_, j) => j !== i) };
  }
  return null;
}
