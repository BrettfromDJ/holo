/**
 * eBay sold-listing data from TCG API (`GET /v1/cards/:id/prices?include=ebay_sales`),
 * as the app uses it. The window is the 30 days before `asOf`.
 */

export interface EbayStats {
  /** Median sold price in the window; null when nothing sold. */
  median: number | null;
  /** Sales the median rests on. */
  count: number;
  /** Latest sale, in or out of the window (the accepted offer on Best Offer sales). */
  lastPrice: number | null;
  lastSold: string | null;
}

export interface EbaySale {
  soldDate: string;
  price: number;
  bestOffer: boolean;
  /** Asking price on Best Offer sales. */
  listPrice: number | null;
  /** Grade label (e.g. "PSA 10"); null when ungraded. */
  grade: string | null;
  /** Condition from the title, ungraded sales only (Near Mint … Damaged). */
  condition: string | null;
  title: string;
  url: string;
}

export interface EbaySales {
  printing: string | null;
  /** Ungraded copies, every condition. */
  ungraded: EbayStats;
  /** Each grade that has sold, keyed by label ("PSA 10", "BGS 9.5"). */
  graded: Record<string, EbayStats>;
  /** Newest first. */
  sales: EbaySale[];
  /** When the sales were last read; the window ends here. */
  asOf: string;
  /** Days of the 30-day window the stored ungraded sales cover (30 = complete). */
  days: number | null;
}
