import type { Product } from "../types";

export interface ExploreSet {
  slug: string;
  gameSlug: string;
  gameName: string;
  name: string;
  releaseDate: string | null;
  imageUrl: string | null;
  iconUrl: string | null;
  productCount: number | null;
  /** False until the daily catalog sync has loaded this set's products. */
  loaded: boolean;
  syncedAt: string | null;
}

export interface ExploreProduct {
  product: Product;
  printing: string | null;
  market: number | null;
  priceUpdatedAt: string | null;
}

export interface ExploreGame {
  slug: string;
  name: string;
  logoUrl: string | null;
  /** Sets in Holo's catalog for this brand, and how many are loaded. */
  sets: number;
  loadedSets: number;
  /** Total cards reported by the source, when known. */
  cardCount: number | null;
}
