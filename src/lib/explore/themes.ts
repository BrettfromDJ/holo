import type { ExploreProduct } from "./types";

/**
 * Home's themed collections ("Skyridge holos", "Charizard through the years"…): rules over our
 * own catalog, not hand-made lists, so they fill themselves and keep up with new sets. Home
 * picks a few each time the app opens, leaning toward what you collect. Each has a look, so no
 * two sections on Home look the same. New ones are added here, and AI (OpenAI) proposes a few more
 * each week (`theme-ideas.ts`) in the same shape.
 */
export type ThemeLook = "billboard" | "fan" | "timeline" | "mosaic" | "ladder" | "spotlight";
export const THEME_LOOKS: ThemeLook[] = ["billboard", "fan", "timeline", "mosaic", "ladder", "spotlight"];

export interface ThemeRule {
  id: string;
  title: string;
  /** One line under the title. */
  blurb: string;
  look: ThemeLook;
  /** Any of these in the set's name (e.g. "Skyridge", "1st Edition"). */
  sets?: string[];
  /** Any of these in the card's name (e.g. "Charizard", "Dark "). */
  names?: string[];
  /** Any of these in the rarity (e.g. "Holo", "Special Illustration"). */
  rarities?: string[];
  /** Any of these at the start of the card number (e.g. "TG", "SV"). */
  numbers?: string[];
  minPrice?: number;
  maxPrice?: number;
  /** The Pokémon it's about, to lean it toward people who collect them. */
  pokemon?: string[];
  era?: "vintage" | "midEra" | "modern";
  /** AI's idea this week (shown with a New tag). */
  fresh?: boolean;
}

/** A theme with its cards, as Home gets it. */
export interface Theme extends Omit<ThemeRule, "sets" | "names" | "rarities" | "numbers" | "minPrice" | "maxPrice"> {
  hits: ExploreProduct[];
}

const EEVEE = ["Eevee", "Vaporeon", "Jolteon", "Flareon", "Espeon", "Umbreon", "Leafeon", "Glaceon", "Sylveon"];
const NEO = ["Neo Genesis", "Neo Discovery", "Neo Revelation", "Neo Destiny"];
const EX_ERA = ["Team Rocket Returns", "Deoxys", "Emerald", "Unseen Forces", "Delta Species", "Legend Maker", "Holon Phantoms", "Crystal Guardians", "Dragon Frontiers", "Power Keepers"];

export const THEMES: ThemeRule[] = [
  { id: "skyridge-holos", title: "Skyridge holos", blurb: "The last Wizards set, and the rarest holos of the era.", look: "mosaic", sets: ["Skyridge"], rarities: ["Holo"], era: "vintage", minPrice: 20 },
  { id: "first-edition-holos", title: "1st Edition holos", blurb: "The stamp that started it all.", look: "billboard", sets: ["1st Edition"], rarities: ["Holo"], era: "vintage", minPrice: 40 },
  { id: "charizard-years", title: "Charizard through the years", blurb: "From Base Set to today, one set at a time.", look: "timeline", names: ["Charizard"], pokemon: ["Charizard"], minPrice: 5 },
  { id: "pikachu-years", title: "Pikachu through the years", blurb: "The face of the hobby, set by set.", look: "timeline", names: ["Pikachu"], pokemon: ["Pikachu"], minPrice: 5 },
  { id: "gengar-ladder", title: "Every price of Gengar", blurb: "From pocket money to grail, one step at a time.", look: "ladder", names: ["Gengar"], pokemon: ["Gengar"], minPrice: 1 },
  { id: "eeveelutions", title: "Eeveelutions", blurb: "Eevee and all eight evolutions at their best.", look: "mosaic", names: EEVEE, rarities: ["Illustration", "Secret", "Ultra"], pokemon: EEVEE, minPrice: 15 },
  { id: "umbreon-spotlight", title: "Umbreon in the spotlight", blurb: "The moonlight Pokémon's most wanted card.", look: "spotlight", names: ["Umbreon"], pokemon: ["Umbreon"], minPrice: 30 },
  { id: "delta-species", title: "Delta Species", blurb: "Pokémon in types they were never meant to be.", look: "fan", sets: ["Delta Species", "Holon Phantoms", "Dragon Frontiers", "Crystal Guardians", "Legend Maker"], rarities: ["Holo", "Rare"], era: "vintage", minPrice: 10 },
  { id: "gold-stars", title: "Gold Stars", blurb: "The EX era's rarest pulls, one or two a set.", look: "spotlight", sets: EX_ERA, names: [" Star", "★"], era: "vintage", minPrice: 100 },
  { id: "shining", title: "Shining Pokémon", blurb: "Neo's original shinies, and the ones that followed.", look: "fan", names: ["Shining "], minPrice: 15 },
  { id: "neo-holos", title: "Neo era holos", blurb: "Johto arrives: Genesis to Destiny.", look: "fan", sets: NEO, rarities: ["Holo"], era: "vintage", minPrice: 15 },
  { id: "dark-pokemon", title: "Team Rocket's dark side", blurb: "Dark Pokémon from the Team Rocket sets.", look: "mosaic", names: ["Dark "], era: "vintage", minPrice: 10 },
  { id: "gym-leaders", title: "Gym leaders' Pokémon", blurb: "Brock's, Misty's, Sabrina's and the rest.", look: "fan", names: ["Brock's", "Misty's", "Erika's", "Surge's", "Sabrina's", "Koga's", "Blaine's", "Giovanni's"], rarities: ["Holo"], minPrice: 10 },
  { id: "grail-sirs", title: "Modern grails", blurb: "The special illustration rares everyone chases.", look: "billboard", rarities: ["Special Illustration"], era: "modern", minPrice: 100 },
  { id: "art-under-50", title: "Alt arts under $50", blurb: "Gallery-worthy art that won't break the bank.", look: "fan", rarities: ["Illustration Rare"], era: "modern", minPrice: 10, maxPrice: 50 },
  { id: "trainer-gallery", title: "Trainer Gallery", blurb: "Pokémon with the people who raised them.", look: "mosaic", numbers: ["TG"], minPrice: 3 },
  { id: "shiny-vault", title: "Shiny Vault", blurb: "Hidden Fates' shiny subset, all black and gold.", look: "mosaic", sets: ["Hidden Fates"], numbers: ["SV"], minPrice: 5 },
  { id: "galarian-gallery", title: "Galarian Gallery", blurb: "Crown Zenith's art cards, start to finish.", look: "fan", sets: ["Crown Zenith"], numbers: ["GG"], minPrice: 3 },
  { id: "radiant", title: "Radiant Pokémon", blurb: "One per deck, all shine.", look: "mosaic", names: ["Radiant "], era: "modern", minPrice: 2 },
  { id: "legendary-birds", title: "The legendary birds", blurb: "Articuno, Zapdos and Moltres, through the eras.", look: "fan", names: ["Articuno", "Zapdos", "Moltres"], pokemon: ["Articuno", "Zapdos", "Moltres"], minPrice: 15 },
  { id: "kanto-starters", title: "Kanto starters", blurb: "Bulbasaur, Charmander and Squirtle, dressed up.", look: "mosaic", names: ["Bulbasaur", "Charmander", "Squirtle", "Ivysaur", "Wartortle", "Charmeleon"], rarities: ["Illustration", "Holo"], minPrice: 10 },
  { id: "dragons", title: "Here be dragons", blurb: "Dragonite, Rayquaza, Garchomp and friends.", look: "billboard", names: ["Dragonite", "Rayquaza", "Garchomp", "Salamence", "Latios", "Latias"], pokemon: ["Dragonite", "Rayquaza", "Garchomp", "Salamence"], minPrice: 40 },
  { id: "lugia-years", title: "Lugia through the years", blurb: "Since Neo Genesis, a guardian of the sea.", look: "timeline", names: ["Lugia"], pokemon: ["Lugia"], minPrice: 5 },
  { id: "mew-years", title: "Mew through the years", blurb: "The rarest Pokémon, everywhere at once.", look: "timeline", names: ["Mew"], pokemon: ["Mew"], minPrice: 5 },
  { id: "mewtwo-ladder", title: "Every price of Mewtwo", blurb: "The original legend, at every budget.", look: "ladder", names: ["Mewtwo"], pokemon: ["Mewtwo"], minPrice: 1 },
  { id: "snorlax-ladder", title: "Every price of Snorlax", blurb: "A big Pokémon for any size of wallet.", look: "ladder", names: ["Snorlax"], pokemon: ["Snorlax"], minPrice: 1 },
  { id: "rayquaza-spotlight", title: "Rayquaza in the spotlight", blurb: "The sky-high pull of the dragon era.", look: "spotlight", names: ["Rayquaza"], pokemon: ["Rayquaza"], minPrice: 50 },
  { id: "151-hits", title: "The best of 151", blurb: "The original 151, back in full art.", look: "billboard", sets: ["151"], minPrice: 20 },
  { id: "evolving-skies", title: "Evolving Skies chase", blurb: "The set that made alt arts famous.", look: "mosaic", sets: ["Evolving Skies"], minPrice: 40 },
  { id: "prismatic", title: "Prismatic Evolutions", blurb: "Eevee's set, and its most wanted cards.", look: "fan", sets: ["Prismatic Evolutions"], minPrice: 20 },
  { id: "vintage-under-40", title: "Vintage holos under $40", blurb: "Wizards-era shine for less than you'd think.", look: "fan", rarities: ["Holo"], era: "vintage", minPrice: 10, maxPrice: 40 },
  { id: "promo-stars", title: "Black Star promos", blurb: "Cards you couldn't pull from a pack.", look: "mosaic", sets: ["Promo"], minPrice: 15 },
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
  if (p.product.kind !== "single" || p.market === null) return false;
  if (!/pok/i.test(p.gameName ?? "pokemon")) return false;
  if (rule.minPrice !== undefined && p.market < rule.minPrice) return false;
  if (rule.maxPrice !== undefined && p.market > rule.maxPrice) return false;
  if (!has(p.product.setName, rule.sets) || !named(p.product.name, rule.names) || !has(p.product.rarity, rule.rarities)) return false;
  if (rule.numbers?.length && !rule.numbers.some((n) => (p.product.number ?? "").toUpperCase().startsWith(n.toUpperCase()))) return false;
  if (rule.era && eraOfDate(p.releaseDate) !== rule.era) return false;
  return true;
}

/** The cards a theme shows, in its look's order (from everything that fits). */
export function pickFor(rule: ThemeRule, all: ExploreProduct[], limit = 24): ExploreProduct[] {
  // One printing per card: the first (priciest after sorting) wins.
  const seen = new Set<string>();
  const fitting = all
    .filter((p) => fits(rule, p))
    .sort((a, b) => (b.market ?? 0) - (a.market ?? 0))
    .filter((p) => !seen.has(p.product.id) && seen.add(p.product.id));
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
    const asc = [...fitting].reverse();
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
