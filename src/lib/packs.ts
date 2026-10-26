import type { Product } from "./types";

export interface PackCount {
  packs: number;
  /** True when the count comes from the product's name, not a typical-contents default. */
  exact: boolean;
}

const WORDS: Record<string, number> = { one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10, twelve: 12 };

/** "Booster Box" contents differ by game; these are the standard English (or Japanese) configurations. */
const BOX_PACKS: Record<string, number> = {
  pokemon: 36,
  "pokemon-japan": 30,
  magic: 36,
  yugioh: 24,
  onepiece: 24,
  lorcana: 24,
};

function franchiseKey(gameSlug: string | null | undefined): string | null {
  if (!gameSlug) return null;
  const s = gameSlug.toLowerCase();
  if (/pokemon/.test(s)) return /japan/.test(s) ? "pokemon-japan" : "pokemon";
  if (/magic/.test(s)) return "magic";
  if (/yu-?gi-?oh/.test(s)) return "yugioh";
  if (/one-?piece/.test(s)) return "onepiece";
  if (/lorcana/.test(s)) return "lorcana";
  return null;
}

/**
 * How many booster packs a sealed product contains, or null when it can't be
 * told reliably. An explicit count in the name wins ("36 Packs", "3-Pack");
 * otherwise well-known product types use their standard contents. Booster
 * boxes depend on the game, so they need `gameSlug`.
 */
export function packCount(product: Pick<Product, "name" | "kind">, gameSlug?: string | null): PackCount | null {
  if (product.kind !== "sealed") return null;
  const name = product.name.toLowerCase().replace(/\([^)]*\b(case|lot|set of)\b[^)]*\)/g, " ");
  // Cases and multi-box lots would need a box count too; leave them out.
  if (/\bcase\b|\blot\b|\bx\s?\d+\b|\d+\s?x\b/.test(name)) return null;

  const explicit = name.match(/\b(\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|twelve)[\s-]*(?:booster[\s-]*)?packs?\b/);
  if (explicit) {
    const n = WORDS[explicit[1]] ?? Number(explicit[1]);
    if (n > 0) return { packs: n, exact: true };
  }

  if (/\b(single|sleeved)? ?booster pack\b|\bsleeved booster\b/.test(name) && !/box|bundle|display|blister/.test(name)) return { packs: 1, exact: false };
  if (/elite trainer box|\betb\b/.test(name)) return { packs: 9, exact: false };
  if (/booster bundle/.test(name)) return { packs: 6, exact: false };
  if (/collector booster (box|display)/.test(name)) return { packs: 12, exact: false };
  if (/set booster (box|display)/.test(name)) return { packs: 30, exact: false };
  if (/(play|draft) booster (box|display)/.test(name)) return { packs: 36, exact: false };
  if (/booster (box|display)/.test(name)) {
    const key = franchiseKey(gameSlug);
    if (key && BOX_PACKS[key]) return { packs: BOX_PACKS[key], exact: false };
  }
  return null;
}

/** Market price divided across packs, when both are known. */
export function pricePerPack(price: number | null, count: PackCount | null): number | null {
  if (price === null || !count) return null;
  return price / count.packs;
}
