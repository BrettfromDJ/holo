import type { DataSource, NormalizedPrice, PricePoint, Product } from "../types";

export type ProductTypeFilter = "all" | "cards" | "sealed";

export interface SearchQuery {
  q: string;
  type: ProductTypeFilter;
  page?: number;
  perPage?: number;
}

/** A catalog search hit with the source's primary-printing price. */
export interface SearchHit {
  product: Product;
  printing: string | null;
  market: number | null;
  priceUpdatedAt: string | null;
}

export interface SearchResult {
  hits: SearchHit[];
  total: number;
  hasMore: boolean;
  /** Set when the exact query found nothing and a looser one was used. */
  relaxedQuery?: string | null;
}

export interface SetInfo {
  id: string;
  name: string;
  abbreviation: string | null;
  releaseDate: string | null;
  iconUrl: string | null;
  imageUrl: string | null;
  cardCount: number | null;
}

export interface HistoryResult {
  points: PricePoint[];
  /** False when the subscription tier doesn't include history. */
  available: boolean;
  reason?: string;
}

export interface MoverHit {
  product: Product;
  printing: string | null;
  market: number;
  changePct: number;
}

/**
 * Pricing sources implement this interface. The collection database only
 * stores `Product.id` (`${source}:${externalId}`) and printing names, so a
 * new source can be added without touching holdings or transactions.
 */
export interface PricingProvider {
  readonly source: DataSource;
  search(query: SearchQuery): Promise<SearchResult>;
  getProduct(externalId: string): Promise<Product>;
  /** One row per printing. */
  getPrices(externalId: string): Promise<NormalizedPrice[]>;
  getHistory(externalId: string, printing: string | null, range: "month" | "quarter" | "year" | "all"): Promise<HistoryResult>;
  /** All sets for the game, newest first. */
  listSets(): Promise<SetInfo[]>;
  /** Products in one set, optionally limited to cards or sealed. */
  setProducts(setId: string, type: ProductTypeFilter): Promise<SearchHit[]>;
  topMovers(params: { direction: "up" | "down"; period: "24h" | "7d" | "30d"; type?: ProductTypeFilter; limit?: number }): Promise<MoverHit[]>;
}

export class PricingUnavailableError extends Error {
  constructor(
    message: string,
    readonly code: "not_configured" | "rate_limited" | "tier" | "auth" | "not_found" | "upstream",
    readonly retryAfter?: number,
  ) {
    super(message);
  }
}
