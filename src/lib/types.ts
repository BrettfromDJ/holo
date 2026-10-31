/**
 * Core domain types shared by the UI, the financial engine and the repositories.
 *
 * Money is stored as plain numbers in the user's currency (USD for TCG API data).
 * Calendar dates are ISO `YYYY-MM-DD` strings so they sort lexically and never
 * shift across time zones.
 */

export type ISODate = string;

/** Where a catalog record or price came from. New pricing sources plug in here. */
export type DataSource = "tcgapi" | "manual" | "sample" | "pricecharting";

/** High-level bucket used for allocation and filtering. */
export type ProductKind = "single" | "sealed";

export interface Product {
  /** Stable internal id: `${source}:${externalId}` (e.g. `tcgapi:523161`). */
  id: string;
  source: DataSource;
  /** Identifier at the source (TCG API card id). */
  externalId: string;
  name: string;
  setName: string | null;
  setId: string | null;
  number: string | null;
  rarity: string | null;
  /** Product type exactly as the source reports it (e.g. "Booster Box"). */
  productType: string | null;
  kind: ProductKind;
  imageUrl: string | null;
  tcgplayerId: number | null;
  tcgplayerUrl: string | null;
  /** Printings the source knows about (e.g. "Normal", "Holofoil"). */
  printings?: string[];
}

export type Condition =
  | "Sealed"
  | "Near Mint"
  | "Lightly Played"
  | "Moderately Played"
  | "Heavily Played"
  | "Damaged";

export const CONDITIONS: Condition[] = [
  "Sealed",
  "Near Mint",
  "Lightly Played",
  "Moderately Played",
  "Heavily Played",
  "Damaged",
];

export interface Grade {
  company: string; // PSA, BGS, CGC...
  grade: string; // "10", "9.5"
}

/** What makes two units interchangeable for cost-basis purposes. */
export interface HoldingIdentity {
  productId: string;
  printing: string | null;
  condition: Condition;
  grade: Grade | null;
}

export type TransactionType = "purchase" | "sale" | "adjustment" | "correction";

export interface Transaction extends HoldingIdentity {
  id: string;
  type: TransactionType;
  date: ISODate;
  /**
   * Units. Always positive for purchases and sales. Signed for adjustments
   * (+ found / gifted / pulled, − lost / opened / damaged).
   */
  quantity: number;
  /** Purchase: unit cost. Sale: unit sale price. Adjustment (+): unit cost basis assigned. */
  unitPrice: number;
  fees: number;
  shipping: number;
  tax: number;
  source?: string | null;
  notes?: string | null;
  /**
   * For `correction` rows: the transaction being corrected. The correction's own
   * fields replace the original's economics. A correction with quantity 0 voids it.
   */
  correctsId?: string | null;
  createdAt: string;
}

export type PriceStatus = "live" | "stale" | "unavailable";

/** Normalized current price, independent of the source that produced it. */
export interface NormalizedPrice {
  productId: string;
  printing: string | null;
  /** Market price. `null` means unknown — never treat it as zero. */
  market: number | null;
  low: number | null;
  /** Percentage changes as reported by the source, when available. */
  change24hPct: number | null;
  change7dPct: number | null;
  change30dPct: number | null;
  /** When the source last updated this price. */
  updatedAt: string | null;
  /** When we last fetched successfully. */
  fetchedAt: string | null;
  source: DataSource;
  status: PriceStatus;
}

export interface PricePoint {
  date: ISODate;
  price: number;
}

export interface WatchlistItem {
  id: string;
  productId: string;
  printing: string | null;
  targetPrice: number | null;
  notes?: string | null;
  addedAt: string;
}

export interface Preferences {
  currency: "USD";
  defaultView: "grid" | "list";
  chartRange: ChartRange;
  /** Monthly spending limit for purchases (incl. fees), or null for none. */
  monthlyBudget?: number | null;
}

export type ChartRange = "1D" | "1W" | "1M" | "3M" | "1Y" | "ALL";

/** Everything a collection view needs. Loaded through a repository. */
export interface CollectionData {
  products: Record<string, Product>;
  transactions: Transaction[];
  watchlist: WatchlistItem[];
  /** Keyed by `priceKey(productId, printing)`. */
  prices: Record<string, NormalizedPrice>;
  /** Daily price history keyed by `priceKey`, sorted ascending by date. */
  history: Record<string, PricePoint[]>;
  /** Manual valuations for graded holdings keyed by `holdingKey`. */
  manualValues: Record<string, { value: number; date: ISODate }>;
  /**
   * What a played condition actually sells for, as a share of Near Mint, keyed
   * `${priceKey}|${condition}` (from TCGplayer's per-condition prices). Missing: the estimate.
   */
  conditionShares?: Record<string, number>;
  preferences: Preferences;
}

export const DEFAULT_PREFERENCES: Preferences = {
  currency: "USD",
  defaultView: "grid",
  chartRange: "1M",
  monthlyBudget: null,
};

export function priceKey(productId: string, printing: string | null): string {
  return `${productId}|${printing ?? ""}`;
}

export function holdingKey(h: HoldingIdentity): string {
  const grade = h.grade ? `${h.grade.company} ${h.grade.grade}` : "";
  return [h.productId, h.printing ?? "", h.condition, grade].join("|");
}

export function isGraded(h: HoldingIdentity): boolean {
  return h.grade !== null;
}
