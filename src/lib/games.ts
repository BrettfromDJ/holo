/**
 * Game (catalog brand) names and order, the same as the app's `MasterSetsView.shortName` and
 * `ExploreGame.ordered`: short names ("Magic", "Yu-Gi-Oh!", "Pokémon Japan") and the owner's
 * order (Pokémon, One Piece, Lorcana, Magic, the rest by set count, Pokémon Japan last).
 */

const KNOWN: Record<string, string> = {
  pokemon: "Pokémon",
  "pokémon": "Pokémon",
  pokemonjapan: "Pokémon Japan",
  "pokémonjapan": "Pokémon Japan",
  yugioh: "Yu-Gi-Oh!",
  magicthegathering: "Magic",
  onepiececardgame: "One Piece",
  onepiece: "One Piece",
  disneylorcana: "Lorcana",
  lorcana: "Lorcana",
  dragonballsuperfusionworld: "Dragon Ball",
  fleshandblood: "Flesh and Blood",
  digimoncardgame: "Digimon",
  starwarsunlimited: "Star Wars",
  weissschwarz: "Weiss Schwarz",
};

/** "Magic: The Gathering" → "Magic", "Disney Lorcana" → "Lorcana", "YuGiOh" → "Yu-Gi-Oh!". */
export function shortGameName(name: string | null | undefined): string {
  if (!name) return "";
  const key = name.toLowerCase().replace(/[^\p{L}]/gu, "");
  const known = KNOWN[key];
  if (known) return known;
  let n = name;
  for (const cut of [": The Gathering", " Trading Card Game", " Card Game", " TCG", " CCG"]) {
    const i = n.toLowerCase().lastIndexOf(cut.toLowerCase());
    if (i >= 0) n = n.slice(0, i) + n.slice(i + cut.length);
  }
  if (n.startsWith("Disney ")) n = n.slice(7);
  return n.trim();
}

function gameRank(name: string): number {
  switch (shortGameName(name)) {
    case "Pokémon":
      return 0;
    case "One Piece":
      return 1;
    case "Lorcana":
      return 2;
    case "Magic":
      return 3;
    case "Pokémon Japan":
      return 5;
    default:
      return 4;
  }
}

/** Games in the owner's order: Pokémon, One Piece, Lorcana, Magic, the rest by set count, Pokémon Japan last. */
export function orderGames<T extends { name: string; sets: number }>(games: readonly T[]): T[] {
  return [...games].sort((a, b) => gameRank(a.name) - gameRank(b.name) || b.sets - a.sets);
}

/** "33K", "1.2K", "240": compact counts like the app's `.compactName`. */
export function compactCount(n: number): string {
  if (n >= 1_000_000) return `${trim(n / 1_000_000)}M`;
  if (n >= 1000) return `${trim(n / 1000)}K`;
  return String(Math.round(n));
}

function trim(v: number): string {
  // Swift's compactName keeps up to 2 significant decimals under 10 ("1.2K"), whole above ("33K").
  return v >= 10 ? String(Math.round(v)) : String(Math.round(v * 10) / 10);
}
