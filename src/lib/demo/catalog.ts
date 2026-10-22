import type { Product } from "../types";

/**
 * SAMPLE DATA — fictional prices for demonstrating the app without
 * credentials. Product ids use the `sample:` source so they can never collide
 * with, or be mixed into, a real collection. Prices here are illustrative only
 * and are never presented as live market data.
 */

export interface SampleProduct extends Product {
  /** Illustrative "today" price. */
  samplePrice: number;
  /** Illustrative price at the start of the generated history. */
  sampleStartPrice: number;
  /** Volatility of the generated sample series. */
  vol: number;
}

const card = (setCode: string, num: string) => `https://images.pokemontcg.io/${setCode}/${num}_hires.png`;

function sp(
  slug: string,
  name: string,
  setName: string,
  productType: string,
  kind: Product["kind"],
  prices: [start: number, now: number],
  extra: Partial<Product> & { vol?: number } = {},
): SampleProduct {
  const { vol = 0.012, ...rest } = extra;
  return {
    id: `sample:${slug}`,
    source: "sample",
    externalId: slug,
    name,
    setName,
    setId: setName.toLowerCase().replace(/[^a-z0-9]+/g, "-"),
    number: null,
    rarity: null,
    productType,
    kind,
    imageUrl: null,
    tcgplayerId: null,
    tcgplayerUrl: null,
    printings: kind === "single" ? ["Holofoil"] : ["Normal"],
    sampleStartPrice: prices[0],
    samplePrice: prices[1],
    vol,
    ...rest,
  };
}

export const SAMPLE_PRODUCTS: SampleProduct[] = [
  // Sealed
  sp("es-bb", "Evolving Skies Booster Box", "Evolving Skies", "Booster Box", "sealed", [640, 1184.5], { vol: 0.009 }),
  sp("151-bundle", "Scarlet & Violet—151 Booster Bundle", "Scarlet & Violet—151", "Booster Bundle", "sealed", [41, 63.4]),
  sp("cz-etb", "Crown Zenith Elite Trainer Box", "Crown Zenith", "Elite Trainer Box", "sealed", [58, 96.2]),
  sp("pe-etb", "Prismatic Evolutions Elite Trainer Box", "Prismatic Evolutions", "Elite Trainer Box", "sealed", [142, 118.75], { vol: 0.016 }),
  sp("ss-bb", "Surging Sparks Booster Box", "Surging Sparks", "Booster Box", "sealed", [152, 214.9]),
  sp("151-upc", "Scarlet & Violet—151 Ultra Premium Collection", "Scarlet & Violet—151", "Ultra Premium Collection", "sealed", [118, 212.3]),
  sp("cel-upc", "Celebrations Ultra Premium Collection", "Celebrations", "Ultra Premium Collection", "sealed", [210, 338.6]),
  sp("pf-tin", "Paldean Fates Tin", "Paldean Fates", "Tin", "sealed", [27, 29.85]),
  sp("tm-bb", "Twilight Masquerade Booster Box", "Twilight Masquerade", "Booster Box", "sealed", [168, 139.4]),
  sp("jt-pack", "Journey Together Booster Pack", "Journey Together", "Booster Pack", "sealed", [5.4, 4.62], { vol: 0.02 }),
  sp("of-etb", "Obsidian Flames Elite Trainer Box", "Obsidian Flames", "Elite Trainer Box", "sealed", [44, 61.2]),
  sp("pr-bb", "Paradox Rift Booster Box", "Paradox Rift", "Booster Box", "sealed", [128, 172.5]),
  sp("pe-bundle", "Prismatic Evolutions Booster Bundle", "Prismatic Evolutions", "Booster Bundle", "sealed", [62, 54.8], { vol: 0.018 }),
  sp("dr-etb", "Destined Rivals Elite Trainer Box", "Destined Rivals", "Elite Trainer Box", "sealed", [74, 69.9]),
  sp("cc-box", "Charizard ex Premium Collection", "Scarlet & Violet Promos", "Collection Box", "sealed", [39, 47.5]),

  // Singles
  sp("umbreon-vmax-alt", "Umbreon VMAX (Alternate Full Art)", "Evolving Skies", "Cards", "single", [520, 1392.0], {
    number: "215/203",
    rarity: "Secret Rare",
    imageUrl: card("swsh7", "215"),
    vol: 0.014,
  }),
  sp("rayquaza-vmax-alt", "Rayquaza VMAX (Alternate Full Art)", "Evolving Skies", "Cards", "single", [270, 548.0], {
    number: "218/203",
    rarity: "Secret Rare",
    imageUrl: card("swsh7", "218"),
    vol: 0.015,
  }),
  sp("charizard-ex-151", "Charizard ex - 199/165", "Scarlet & Violet—151", "Cards", "single", [118, 104.25], {
    number: "199/165",
    rarity: "Special Illustration Rare",
    imageUrl: card("sv3pt5", "199"),
  }),
  sp("mew-ex-gold", "Mew ex - 205/165", "Scarlet & Violet—151", "Cards", "single", [44, 27.9], {
    number: "205/165",
    rarity: "Hyper Rare",
    imageUrl: card("sv3pt5", "205"),
  }),
  sp("pikachu-ex-ss", "Pikachu ex - 238/191", "Surging Sparks", "Cards", "single", [285, 371.5], {
    number: "238/191",
    rarity: "Special Illustration Rare",
    imageUrl: card("sv8", "238"),
    vol: 0.017,
  }),
  sp("giratina-v-alt", "Giratina V (Alternate Full Art)", "Lost Origin", "Cards", "single", [215, 318.4], {
    number: "186/196",
    rarity: "Ultra Rare",
    imageUrl: card("swsh11", "186"),
  }),
  sp("charizard-base", "Charizard (Base Set)", "Base Set", "Cards", "single", [520, 455.0], {
    number: "4/102",
    rarity: "Holo Rare",
    imageUrl: card("base1", "4"),
    vol: 0.01,
  }),
  sp("charizard-ex-of", "Charizard ex - 223/197", "Obsidian Flames", "Cards", "single", [72, 58.3], {
    number: "223/197",
    rarity: "Special Illustration Rare",
    imageUrl: card("sv3", "223"),
  }),
  sp("lugia-v-alt", "Lugia V (Alternate Full Art)", "Silver Tempest", "Cards", "single", [190, 262.0], {
    number: "186/195",
    rarity: "Ultra Rare",
    imageUrl: card("swsh12", "186"),
  }),
  sp("gengar-vmax-alt", "Gengar VMAX (Alternate Art Secret)", "Fusion Strike", "Cards", "single", [310, 404.0], {
    number: "271/264",
    rarity: "Secret Rare",
    imageUrl: card("swsh8", "271"),
  }),
  sp("espeon-vmax-alt", "Espeon VMAX (Alternate Art Secret)", "Evolving Skies", "Cards", "single", [320, 512.0], {
    number: "270/203",
    rarity: "Secret Rare",
    imageUrl: card("swsh7", "270"),
  }),
];

export const SAMPLE_BY_ID: Record<string, SampleProduct> = Object.fromEntries(SAMPLE_PRODUCTS.map((p) => [p.id, p]));
