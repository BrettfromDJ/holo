import { isOversized } from "./movers";
import type { ExploreProduct } from "./types";

/**
 * Home's themed collections, from the owner's discovery playbook ("The Art of Card Discovery"):
 * price finds, grails, art, vintage, Pokémon and collections that change over time. Each is a
 * rule, filled on the server (`src/lib/server/themes.ts`) in one of these ways (`source`):
 * - "rule" (default): cards whose name, set, rarity, number, price and era fit;
 * - "price": the same, but read from the priciest cards down (grails, price bands);
 * - "ai": cards the AI picks each week from our illustration cards, for art themes a rule can't
 *   see (Tiny Worlds, After Dark…), guided by `brief`;
 * - "market": the day's market lists (trending, today, drops, rediscovered);
 * - "fresh": cards from sets out in the last 90 days;
 * - "popular": cards most kept or watched by Dexora collectors (two people or more).
 * The app shows Collection of the Day at the top of Home and a new mix of four further down each
 * time it opens; `featured` ones (the playbook's launch lineup) come up more often. Each has a
 * look, so no two sections look the same. The AI also proposes 5 new ones a week.
 */
export type ThemeLook = "billboard" | "fan" | "timeline" | "mosaic" | "ladder" | "spotlight";
export const THEME_LOOKS: ThemeLook[] = ["billboard", "fan", "timeline", "mosaic", "ladder", "spotlight"];

export interface ThemeRule {
  id: string;
  title: string;
  /** One line under the title. */
  blurb: string;
  look: ThemeLook;
  source?: "rule" | "price" | "ai" | "market" | "fresh" | "popular";
  /** Any of these in the set's name (e.g. "Skyridge", "1st Edition"). */
  sets?: string[];
  /** Any of these in the card's name, as whole words (e.g. "Charizard", "Dark "). */
  names?: string[];
  /** Any of these in the rarity (e.g. "Holo", "Special Illustration"). */
  rarities?: string[];
  /** None of these in the rarity ("Illustration Rare" without "Special"). */
  notRarities?: string[];
  /** Any of these at the start of the card number (e.g. "TG", "SV"). */
  numbers?: string[];
  minPrice?: number;
  maxPrice?: number;
  /** The Pokémon it's about, to lean it toward people who collect them. */
  pokemon?: string[];
  era?: "vintage" | "midEra" | "modern";
  /** Japanese cards only (otherwise Japanese cards are left out, so nothing shows twice). */
  japanese?: boolean;
  /** For "market": which list. */
  market?: "trending" | "today" | "drops" | "rediscovered";
  /** For "ai": what to look for in the art. */
  brief?: string;
  /** The playbook's launch lineup: shown more often. */
  featured?: boolean;
  /** AI's idea this week (shown with a New tag). */
  fresh?: boolean;
}

/** A theme with its cards, as Home gets it. */
export interface Theme {
  id: string;
  title: string;
  blurb: string;
  look: ThemeLook;
  pokemon?: string[];
  era?: "vintage" | "midEra" | "modern";
  featured?: boolean;
  fresh?: boolean;
  /** Picked by AI (art themes). */
  curated?: boolean;
  hits: ExploreProduct[];
}

const EEVEE = ["Eevee", "Vaporeon", "Jolteon", "Flareon", "Espeon", "Umbreon", "Leafeon", "Glaceon", "Sylveon"];
const NEO = ["Neo Genesis", "Neo Discovery", "Neo Revelation", "Neo Destiny"];
const EX_ERA = ["Ruby and Sapphire", "Sandstorm", "Dragon", "Team Magma vs Team Aqua", "Hidden Legends", "Fire Red Leaf Green", "Team Rocket Returns", "Deoxys", "Emerald", "Unseen Forces", "Delta Species", "Legend Maker", "Holon Phantoms", "Crystal Guardians", "Dragon Frontiers", "Power Keepers"];
const WOTC = ["Base Set", "Jungle", "Fossil", "Team Rocket", "Gym Heroes", "Gym Challenge", ...NEO, "Legendary Collection", "Expedition", "Aquapolis", "Skyridge", "Southern Islands"];
const ART = ["Illustration", "Full Art"];
const IR = { rarities: ["Illustration Rare"], notRarities: ["Special"] };
const GHOSTS = ["Gengar", "Haunter", "Gastly", "Mimikyu", "Banette", "Dusknoir", "Chandelure", "Drifblim", "Misdreavus", "Mismagius", "Sableye", "Spiritomb", "Dragapult"];
const LEGENDS = ["Mewtwo", "Mew", "Lugia", "Ho-Oh", "Rayquaza", "Groudon", "Kyogre", "Dialga", "Palkia", "Giratina", "Arceus", "Reshiram", "Zekrom", "Xerneas", "Yveltal", "Zacian", "Zamazenta", "Koraidon", "Miraidon", "Articuno", "Zapdos", "Moltres"];
const DRAGONS = ["Dragonite", "Rayquaza", "Garchomp", "Salamence", "Latios", "Latias", "Dragapult", "Giratina", "Kingdra", "Flygon", "Hydreigon", "Goodra"];
const STARTERS = ["Bulbasaur", "Charmander", "Squirtle", "Chikorita", "Cyndaquil", "Totodile", "Treecko", "Torchic", "Mudkip", "Turtwig", "Chimchar", "Piplup", "Snivy", "Tepig", "Oshawott", "Froakie", "Rowlet", "Litten", "Popplio", "Sprigatito", "Fuecoco", "Quaxly"];

export const THEMES: ThemeRule[] = [
  // 01 Price-based discoveries
  { id: "alt-arts-under-50", title: "Alt arts under $50", blurb: "Affordable alternate-art cards.", look: "fan", rarities: ["Illustration"], minPrice: 10, maxPrice: 50, source: "price", featured: true },
  { id: "alt-arts-under-200", title: "Alt arts under $200", blurb: "More premium alternate arts.", look: "mosaic", rarities: ["Illustration"], minPrice: 50, maxPrice: 200, source: "price" },
  { id: "hidden-gems-under-10", title: "Hidden gems under $10", blurb: "Beautiful, overlooked cards.", look: "mosaic", rarities: ART, minPrice: 2, maxPrice: 10, featured: true },
  { id: "the-25-club", title: "The $25 club", blurb: "Cool cards anyone can collect.", look: "fan", rarities: [...ART, "Holo"], minPrice: 18, maxPrice: 25 },
  { id: "budget-grails", title: "Budget grails", blurb: "Desirable cards without grail prices.", look: "spotlight", rarities: ["Special Illustration", "Secret", "Holo"], minPrice: 60, maxPrice: 150, source: "price" },
  { id: "irs-under-20", title: "Illustration rares under $20", blurb: "Affordable illustrated cards.", look: "fan", ...IR, minPrice: 3, maxPrice: 20, featured: true },
  { id: "sirs-under-100", title: "SIRs under $100", blurb: "Special illustration rares for less.", look: "mosaic", rarities: ["Special Illustration"], minPrice: 20, maxPrice: 100 },
  { id: "big-art-small-price", title: "Big art, small price", blurb: "Cards that look way more expensive.", look: "billboard", source: "ai", brief: "dramatic, full-bleed, gallery-quality art on cards that cost little", maxPrice: 25 },
  { id: "the-100-collection", title: "The $100 collection", blurb: "The best-looking cards around $100.", look: "billboard", rarities: [...ART, "Secret", "Holo"], minPrice: 85, maxPrice: 115, source: "price" },
  { id: "affordable-vintage", title: "Affordable vintage", blurb: "Vintage holos that won't break the bank.", look: "fan", rarities: ["Holo"], era: "vintage", minPrice: 8, maxPrice: 40, source: "price" },

  // 02 Grails & iconic cards
  { id: "modern-grails", title: "Modern grails", blurb: "The biggest modern chase cards.", look: "billboard", era: "modern", minPrice: 250, source: "price", featured: true },
  { id: "vintage-grails", title: "Vintage grails", blurb: "The cards collectors dream about.", look: "spotlight", era: "vintage", minPrice: 300, source: "price", featured: true },
  { id: "holy-grails", title: "The holy grails", blurb: "Pokémon's most coveted cards.", look: "billboard", minPrice: 1000, source: "price" },
  { id: "skyridge-holos", title: "Skyridge holos", blurb: "Deep-cut vintage collecting.", look: "mosaic", sets: ["Skyridge"], rarities: ["Holo"], era: "vintage", minPrice: 20, featured: true },
  { id: "crystal-pokemon", title: "Crystal Pokémon", blurb: "The rare Crystal-type cards.", look: "spotlight", sets: ["Aquapolis", "Skyridge", "Expedition"], names: ["Crystal"], era: "vintage", minPrice: 50 },
  { id: "gold-star-legends", title: "Gold Star legends", blurb: "The legendary Gold Star era.", look: "spotlight", sets: EX_ERA, names: [" Star", "★"], era: "vintage", minPrice: 100 },
  { id: "shining-pokemon", title: "Shining Pokémon", blurb: "Classic Neo-era Shining cards.", look: "fan", names: ["Shining "], minPrice: 15 },
  { id: "moonbreon-club", title: "The Moonbreon club", blurb: "Iconic modern Eeveelution chases.", look: "billboard", names: EEVEE, rarities: ["Special Illustration", "Secret", "Ultra", "Illustration"], era: "modern", minPrice: 100, pokemon: EEVEE },
  { id: "charizard-collection", title: "The Charizard collection", blurb: "Iconic Charizards throughout history.", look: "timeline", names: ["Charizard"], pokemon: ["Charizard"], minPrice: 10 },
  { id: "million-dollar-club", title: "The million-dollar club", blurb: "Historically ultra-valuable collectibles.", look: "spotlight", minPrice: 3000, source: "price" },

  // 03 Art-driven (picked by AI from our illustration cards)
  { id: "tiny-worlds", title: "Tiny worlds", blurb: "Art packed with tiny details.", look: "mosaic", source: "ai", brief: "busy, intricate scenes full of small details to discover" },
  { id: "museum", title: "Cards that belong in a museum", blurb: "Jaw-dropping illustration cards.", look: "billboard", source: "ai", brief: "the most acclaimed, painterly, jaw-dropping illustrations", featured: true },
  { id: "after-dark", title: "After dark", blurb: "Nighttime, moonlight and dark art.", look: "fan", source: "ai", brief: "night scenes, moonlight, stars, dark moody palettes" },
  { id: "cozy-pokemon", title: "Cozy Pokémon", blurb: "Warm, peaceful, charming artwork.", look: "mosaic", source: "ai", brief: "warm, calm, homely scenes: napping, eating, relaxing, soft light" },
  { id: "full-art-masterpieces", title: "Full art masterpieces", blurb: "Edge to edge, and every inch counts.", look: "billboard", source: "ai", brief: "the strongest full-art and special illustration compositions" },
  { id: "pokemon-in-the-wild", title: "Pokémon in the wild", blurb: "Pokémon living their lives, out in nature.", look: "fan", source: "ai", brief: "Pokémon in natural habitats: forests, fields, mountains, rivers" },
  { id: "underwater-worlds", title: "Underwater worlds", blurb: "Scenes from under the sea.", look: "mosaic", source: "ai", brief: "underwater scenes, oceans, reefs, deep sea" },
  { id: "art-of-kanto", title: "The art of Kanto", blurb: "The first 151, drawn beautifully.", look: "fan", source: "ai", brief: "original 151 (Kanto) Pokémon with standout illustrations" },
  { id: "beautifully-weird", title: "Beautifully weird", blurb: "Strange, surreal and unforgettable.", look: "mosaic", source: "ai", brief: "surreal, odd, unexpected or experimental art styles" },
  { id: "watercolor-wonders", title: "Watercolor wonders", blurb: "Soft washes and painterly color.", look: "fan", source: "ai", brief: "watercolor, gouache or soft painterly styles" },
  { id: "cards-with-a-story", title: "Cards with a story", blurb: "Art that tells you what happened next.", look: "spotlight", source: "ai", brief: "illustrations that tell a story or connect to other cards" },
  { id: "scenic-pokemon", title: "Scenic Pokémon", blurb: "Landscapes first, Pokémon second.", look: "billboard", source: "ai", brief: "wide landscapes and scenery where the setting is the star" },
  { id: "cutest-cards-ever", title: "The cutest cards ever", blurb: "Adorable, and that's the whole point.", look: "mosaic", source: "ai", brief: "the cutest, most adorable illustrations" },
  { id: "breaks-the-frame", title: "Art that breaks the frame", blurb: "Pokémon bursting out of the card.", look: "spotlight", source: "ai", brief: "art where the Pokémon breaks out of the frame or plays with the card's borders" },

  // 04 Vintage & nostalgic
  { id: "e-reader-era", title: "The e-Reader era", blurb: "Expedition, Aquapolis and Skyridge.", look: "mosaic", sets: ["Expedition", "Aquapolis", "Skyridge"], rarities: ["Holo"], era: "vintage", minPrice: 15 },
  { id: "neo-nostalgia", title: "Neo nostalgia", blurb: "Neo Genesis through Neo Destiny.", look: "fan", sets: NEO, rarities: ["Holo"], era: "vintage", minPrice: 15 },
  { id: "ex-era-gems", title: "EX era gems", blurb: "Classic EX-era treasures.", look: "mosaic", sets: EX_ERA, rarities: ["Holo", "Rare"], era: "vintage", minPrice: 25 },
  { id: "original-151", title: "The original 151", blurb: "Kanto's first Pokémon, back in full art.", look: "billboard", sets: ["151"], minPrice: 15 },
  { id: "delta-species", title: "Delta Species", blurb: "The unique Delta Species era.", look: "fan", sets: ["Delta Species", "Holon Phantoms", "Dragon Frontiers", "Crystal Guardians", "Legend Maker"], rarities: ["Holo", "Rare"], era: "vintage", minPrice: 10 },
  { id: "forgotten-holos", title: "The forgotten holos", blurb: "Underrated vintage holographics.", look: "mosaic", sets: WOTC, rarities: ["Holo"], era: "vintage", minPrice: 10, maxPrice: 45 },
  { id: "old-school-ex", title: "Old school ex", blurb: "The original lowercase ex Pokémon.", look: "fan", sets: EX_ERA, names: ["ex"], era: "vintage", minPrice: 20 },
  { id: "legendary-collection", title: "Legendary Collection", blurb: "Iconic reverse holos and more.", look: "mosaic", sets: ["Legendary Collection"], minPrice: 15 },
  { id: "japanese-exclusives", title: "Japanese exclusives", blurb: "Cards that never got an English release.", look: "fan", japanese: true, rarities: ["Illustration", "Holo", "Promo", "Secret"], minPrice: 20, source: "price", featured: true },
  { id: "wotc-classics", title: "WOTC classics", blurb: "The original Wizards of the Coast sets.", look: "fan", sets: WOTC, rarities: ["Holo"], era: "vintage", minPrice: 30 },

  // 05 Pokémon & characters
  { id: "eevee-and-friends", title: "Eevee & friends", blurb: "The best Eeveelution artwork.", look: "mosaic", names: EEVEE, rarities: ["Illustration", "Secret", "Ultra", "Holo"], pokemon: EEVEE, minPrice: 10, featured: true },
  { id: "ghost-stories", title: "Ghost stories", blurb: "Gengar, Mimikyu, Gastly and friends.", look: "fan", names: GHOSTS, rarities: ["Illustration", "Holo", "Secret", "Ultra"], pokemon: GHOSTS, minPrice: 8 },
  { id: "pikachu-ages", title: "Pikachu through the ages", blurb: "Iconic Pikachu cards.", look: "timeline", names: ["Pikachu"], pokemon: ["Pikachu"], minPrice: 5 },
  { id: "legendary-pokemon", title: "The legendary collection", blurb: "Legendary Pokémon across the eras.", look: "billboard", names: LEGENDS, rarities: ["Illustration", "Holo", "Secret", "Ultra"], pokemon: LEGENDS, minPrice: 40, source: "price" },
  { id: "team-rocket", title: "Team Rocket", blurb: "Villain-themed cards.", look: "mosaic", names: ["Rocket's", "Dark ", "Giovanni"], minPrice: 8 },
  { id: "dragons-den", title: "Dragon's den", blurb: "Dragonite, Rayquaza and more.", look: "spotlight", names: DRAGONS, rarities: ["Illustration", "Holo", "Secret", "Ultra"], pokemon: DRAGONS, minPrice: 25 },
  { id: "starter-pack", title: "Starter pack", blurb: "The most collectible starter Pokémon.", look: "fan", names: STARTERS, rarities: ["Illustration", "Holo", "Secret"], pokemon: STARTERS, minPrice: 8 },
  { id: "trainer-gallery-favorites", title: "Trainer Gallery favorites", blurb: "Standout Pokémon and trainer artwork.", look: "mosaic", numbers: ["TG"], minPrice: 3 },

  // 06 Collections that change over time
  { id: "trending-this-week", title: "Trending this week", blurb: "Cards gaining attention.", look: "mosaic", source: "market", market: "trending" },
  { id: "on-the-rise", title: "On the rise", blurb: "Cards with rising market prices today.", look: "ladder", source: "market", market: "today" },
  { id: "biggest-price-drops", title: "Biggest price drops", blurb: "Cards that have recently fallen in price.", look: "fan", source: "market", market: "drops" },
  { id: "fresh-finds", title: "Fresh finds", blurb: "Recently released cards worth discovering.", look: "billboard", source: "fresh", minPrice: 5, featured: true },
  { id: "sleeper-list", title: "The sleeper list", blurb: "Underappreciated cards worth a second look.", look: "fan", source: "ai", brief: "underappreciated cards with strong art or history that collectors overlook", maxPrice: 60 },
  { id: "under-the-radar", title: "Under the radar", blurb: "Cards with relatively little attention.", look: "mosaic", source: "ai", brief: "quietly great cards few people talk about", maxPrice: 40 },
  { id: "collector-favorites", title: "Collector favorites", blurb: "The cards Dexora collectors keep and watch most.", look: "mosaic", source: "popular" },
  { id: "rediscovered", title: "Rediscovered", blurb: "Older cards getting fresh attention.", look: "spotlight", source: "market", market: "rediscovered" },
  { id: "just-under-100", title: "Just under $100", blurb: "Cards priced just below the line.", look: "fan", rarities: [...ART, "Secret", "Holo", "Ultra"], minPrice: 80, maxPrice: 99.99, source: "price" },
];

/** Release date to era (same cut-offs as `eraOf` in movers.ts). */
export function eraOfDate(d: string | null | undefined): "vintage" | "midEra" | "modern" | null {
  if (!d) return null;
  return d < "2007-05-01" ? "vintage" : d < "2017-02-01" ? "midEra" : "modern";
}

const has = (value: string | null | undefined, any?: string[]) => !any?.length || (value != null && any.some((a) => value.toLowerCase().includes(a.toLowerCase())));
const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
/** A card name with any of these as whole words ("Mew" is not "Mewtwo"). */
const named = (value: string, any?: string[]) =>
  !any?.length || any.some((a) => new RegExp(`${/^\w/.test(a) ? "\\b" : ""}${escape(a)}${/\w$/.test(a) ? "\\b" : ""}`, "i").test(value));

/** Whether a priced card fits the rule (the database read is looser; this is exact). */
export function fits(rule: ThemeRule, p: ExploreProduct): boolean {
  if (p.product.kind !== "single" || p.market === null || isOversized(p.product)) return false;
  if (!/pok/i.test(p.gameName ?? "pokemon")) return false;
  if (Boolean(rule.japanese) !== /japan/i.test(p.gameName ?? "")) return false;
  if (rule.notRarities?.length && rule.notRarities.some((r) => (p.product.rarity ?? "").toLowerCase().includes(r.toLowerCase()))) return false;
  if (rule.minPrice !== undefined && p.market < rule.minPrice) return false;
  if (rule.maxPrice !== undefined && p.market > rule.maxPrice) return false;
  if (!has(p.product.setName, rule.sets) || !named(p.product.name, rule.names) || !has(p.product.rarity, rule.rarities)) return false;
  if (rule.numbers?.length && !rule.numbers.some((n) => (p.product.number ?? "").toUpperCase().startsWith(n.toUpperCase()))) return false;
  if (rule.era && eraOfDate(p.releaseDate) !== rule.era) return false;
  return true;
}

/** The cards a theme shows, in its look's order (from everything that fits). */
export function pickFor(rule: ThemeRule, all: ExploreProduct[], limit = 24, keepOrder = false): ExploreProduct[] {
  // One printing per card: the first (priciest after sorting) wins.
  const seen = new Set<string>();
  const fit = all.filter((p) => fits(rule, p));
  const fitting = (keepOrder ? fit : fit.sort((a, b) => (b.market ?? 0) - (a.market ?? 0))).filter((p) => !seen.has(p.product.id) && seen.add(p.product.id));
  if (rule.look === "timeline") {
    // The priciest card from each set, oldest set first.
    const bySet = new Map<string, ExploreProduct>();
    for (const p of fitting) {
      const key = p.product.setName ?? p.product.id;
      if (!bySet.has(key)) bySet.set(key, p);
    }
    return [...bySet.values()].filter((p) => p.releaseDate).sort((a, b) => (a.releaseDate ?? "").localeCompare(b.releaseDate ?? "")).slice(-14);
  }
  if (rule.look === "ladder") {
    // Steps from the cheapest to the priciest, spread evenly (cheapest first).
    const asc = [...fitting].sort((a, b) => (a.market ?? 0) - (b.market ?? 0));
    if (asc.length <= 7) return asc;
    const steps = 7;
    return Array.from({ length: steps }, (_, i) => asc[Math.round((i * (asc.length - 1)) / (steps - 1))]).filter((p, i, a) => a.indexOf(p) === i);
  }
  return fitting.slice(0, limit);
}

/** A rule as a cheap database filter: PostgREST `or` lists for names, sets and numbers. */
export function orList(column: string, values?: string[], prefix = false): string | null {
  if (!values?.length) return null;
  // Commas and parentheses would break the list; none of our values need them.
  const clean = values.map((v) => v.replace(/[,()]/g, " ")).filter((v) => v.trim());
  return clean.map((v) => `${column}.ilike.${prefix ? "" : "*"}${v}*`).join(",");
}
