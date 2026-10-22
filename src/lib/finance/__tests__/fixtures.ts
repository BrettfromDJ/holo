import { DEFAULT_PREFERENCES, priceKey, type CollectionData, type NormalizedPrice, type Transaction } from "../../types";

let seq = 0;

export function tx(partial: Partial<Transaction> & Pick<Transaction, "type" | "date" | "quantity" | "unitPrice">): Transaction {
  seq++;
  return {
    id: partial.id ?? `t${seq}`,
    productId: "p:box",
    printing: null,
    condition: "Sealed",
    grade: null,
    fees: 0,
    shipping: 0,
    tax: 0,
    createdAt: `2026-01-01T00:00:${String(seq % 60).padStart(2, "0")}.${String(seq).padStart(3, "0")}Z`,
    ...partial,
  };
}

export function price(productId: string, market: number | null, extra: Partial<NormalizedPrice> = {}): NormalizedPrice {
  return {
    productId,
    printing: null,
    market,
    low: null,
    change24hPct: null,
    change7dPct: null,
    change30dPct: null,
    updatedAt: "2026-03-10T00:00:00Z",
    fetchedAt: "2026-03-10T00:00:00Z",
    source: "tcgapi",
    status: market === null ? "unavailable" : "live",
    ...extra,
  };
}

export function data(partial: Partial<CollectionData> = {}): CollectionData {
  return {
    products: {},
    transactions: [],
    watchlist: [],
    prices: {},
    history: {},
    manualValues: {},
    preferences: DEFAULT_PREFERENCES,
    ...partial,
  };
}

export function series(productId: string, points: [string, number][]) {
  return { [priceKey(productId, null)]: points.map(([date, p]) => ({ date, price: p })) };
}
